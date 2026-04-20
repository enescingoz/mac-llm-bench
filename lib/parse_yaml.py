#!/usr/bin/env python3
"""Parse models.yaml without requiring PyYAML.
Falls back to a basic parser if PyYAML is not installed.
Outputs JSON to stdout."""

import json
import sys
import os


def parse_with_pyyaml(filepath):
    import yaml
    with open(filepath) as f:
        return yaml.safe_load(f)


def parse_basic(filepath):
    """Minimal YAML parser that handles our specific models.yaml format."""
    models = {}
    current_model = None
    current_list_key = None
    current_source = None
    in_sources = False

    with open(filepath) as f:
        for line in f:
            stripped = line.rstrip()
            if not stripped or stripped.lstrip().startswith('#'):
                continue

            indent = len(line) - len(line.lstrip())
            content = stripped.strip()

            # Top-level key (indent 0) — e.g., "models:"
            if indent == 0 and content == "models:":
                continue

            # Model ID (indent 2)
            if indent == 2 and content.endswith(':') and not content.startswith('-'):
                current_model = content[:-1].strip()
                models[current_model] = {}
                current_list_key = None
                in_sources = False
                current_source = None
                continue

            if not current_model:
                continue

            # Model property (indent 4)
            if indent == 4 and ':' in content and not content.startswith('-'):
                key, _, val = content.partition(':')
                key = key.strip()
                val = val.strip()

                if val.startswith('[') and val.endswith(']'):
                    items = [x.strip().strip('"').strip("'") for x in val[1:-1].split(',')]
                    models[current_model][key] = items
                elif val == '':
                    current_list_key = key
                    models[current_model][key] = []
                    in_sources = (key in ('sources', 'mlx_sources'))
                    current_source = None
                elif val in ('true', 'false'):
                    models[current_model][key] = val == 'true'
                else:
                    try:
                        models[current_model][key] = int(val)
                    except ValueError:
                        models[current_model][key] = val.strip('"').strip("'")
                continue

            # Source list items (indent 6, starts with -)
            if indent == 6 and content.startswith('-') and in_sources:
                item = content.lstrip('- ').strip()
                if ':' in item:
                    k, _, v = item.partition(':')
                    v = v.strip().strip('"').strip("'")
                    if v in ('true', 'false'):
                        v = v == 'true'
                    current_source = {k.strip(): v}
                    models[current_model][current_list_key].append(current_source)
                continue

            # Source properties (indent 8)
            if indent == 8 and in_sources and current_source and ':' in content:
                k, _, v = content.partition(':')
                k = k.strip()
                v = v.strip().strip('"').strip("'")
                if v in ('true', 'false'):
                    v = v == 'true'
                current_source[k] = v
                continue

    return {"models": models}


def main():
    # Find models.yaml
    if len(sys.argv) > 1:
        filepath = sys.argv[1]
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        filepath = os.path.join(os.path.dirname(script_dir), "models.yaml")

    if not os.path.exists(filepath):
        print(json.dumps({"models": {}}))
        sys.exit(1)

    try:
        data = parse_with_pyyaml(filepath)
    except ImportError:
        data = parse_basic(filepath)

    json.dump(data, sys.stdout)


if __name__ == "__main__":
    main()
