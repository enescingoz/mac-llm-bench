#!/usr/bin/env python3
"""Merge quality benchmark results into an existing speed result JSON file.

Usage:
    python3 lib/merge_quality_result.py --result-file <path> --quality-json '<json-string>'
    python3 lib/merge_quality_result.py --result-file <path> --quality-file <path>

Reads the existing result JSON, merges quality fields into the 'quality' key,
updates schema version to 2.1, and writes back in-place.
Prints the updated file path to stdout on success.
"""

import argparse
import json
import os
import sys
from pathlib import Path


def load_quality_data(args) -> dict:
    """Load quality data from --quality-json string or --quality-file path."""
    if args.quality_json:
        try:
            data = json.loads(args.quality_json)
        except json.JSONDecodeError as e:
            print(f"Error: Failed to parse --quality-json: {e}", file=sys.stderr)
            sys.exit(1)
        return data

    if args.quality_file:
        quality_path = Path(args.quality_file)
        if not quality_path.exists():
            print(f"Error: Quality file not found: {quality_path}", file=sys.stderr)
            sys.exit(1)
        try:
            with open(quality_path) as f:
                return json.load(f)
        except json.JSONDecodeError as e:
            print(f"Error: Failed to parse quality file: {e}", file=sys.stderr)
            sys.exit(1)

    # Should not reach here due to argparse mutual exclusion
    print("Error: Must provide --quality-json or --quality-file", file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Merge quality benchmark results into an existing speed result JSON file"
    )
    parser.add_argument(
        "--result-file",
        required=True,
        help="Path to the existing speed result JSON file to update in-place",
    )

    quality_source = parser.add_mutually_exclusive_group(required=True)
    quality_source.add_argument(
        "--quality-json",
        help="Quality data as a JSON string",
    )
    quality_source.add_argument(
        "--quality-file",
        help="Path to a JSON file containing quality data",
    )

    args = parser.parse_args()

    result_path = Path(args.result_file)
    quality_data = load_quality_data(args)

    if not result_path.exists():
        # Quality benchmarks run before speed benchmarks — preserve data in a standalone file
        print(
            f"Warning: Result file not found. Quality results saved to standalone file.",
            file=sys.stderr,
        )
        standalone = {"version": "2.1", "quality": quality_data}
        result_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(result_path, "w") as f:
                json.dump(standalone, f, indent=2)
                f.write("\n")
        except OSError as e:
            print(f"Error: Could not write standalone file: {e}", file=sys.stderr)
            sys.exit(1)
        print(str(result_path))
        return

    # Read existing result
    try:
        with open(result_path) as f:
            result = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Result file is malformed JSON: {e}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"Error: Could not read result file: {e}", file=sys.stderr)
        sys.exit(1)

    # Verify the file is writable before mutating state
    if not os.access(result_path, os.W_OK):
        print(f"Error: Result file is read-only: {result_path}", file=sys.stderr)
        sys.exit(1)

    # Merge quality fields — extend existing quality section or create it
    existing_quality = result.get("quality", {})
    existing_quality.update(quality_data)
    result["quality"] = existing_quality

    # Bump schema version
    result["version"] = "2.1"

    # Write back in-place (write to temp then rename for atomicity)
    tmp_path = result_path.with_suffix(".json.tmp")
    try:
        with open(tmp_path, "w") as f:
            json.dump(result, f, indent=2)
            f.write("\n")
        tmp_path.replace(result_path)
    except OSError as e:
        print(f"Error: Could not write result file: {e}", file=sys.stderr)
        # Clean up temp file if it was created
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass
        sys.exit(1)

    print(str(result_path))


if __name__ == "__main__":
    main()
