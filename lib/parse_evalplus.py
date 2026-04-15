#!/usr/bin/env python3
"""Parse EvalPlus evaluation output and extract pass@1 scores.

Usage:
    python3 lib/parse_evalplus.py --results-dir <path> --model <model-name> --dataset humaneval

Outputs JSON to stdout with pass@1 scores and eval metadata.
"""

import argparse
import json
import os
import sys
from pathlib import Path


def find_eval_results(results_dir: Path) -> Path | None:
    """Recursively search for eval_results.json under results_dir."""
    for root, _dirs, files in os.walk(results_dir):
        if "eval_results.json" in files:
            return Path(root) / "eval_results.json"
    return None


def extract_pass1(data: dict, dataset: str) -> tuple[float | None, float | None]:
    """Extract humaneval_plus_pass1 and humaneval_base_pass1 from eval_results data.

    Tries multiple possible structures that EvalPlus versions may produce.
    Returns (plus_pass1, base_pass1).
    """
    plus_pass1 = None
    base_pass1 = None

    # Structure 1 (most common): {"eval": {"humaneval": {...}, "humaneval_plus": {...}}}
    eval_section = data.get("eval", {})
    if eval_section:
        # Try humaneval_plus / humaneval_plus keys
        for plus_key in ("humaneval_plus", "humaneval+", "plus"):
            if plus_key in eval_section:
                val = eval_section[plus_key]
                if isinstance(val, dict):
                    plus_pass1 = val.get("pass@1") or val.get("pass_at_1")
                elif isinstance(val, (int, float)):
                    plus_pass1 = float(val)
                if plus_pass1 is not None:
                    break

        for base_key in ("humaneval", "base"):
            if base_key in eval_section:
                val = eval_section[base_key]
                if isinstance(val, dict):
                    base_pass1 = val.get("pass@1") or val.get("pass_at_1")
                elif isinstance(val, (int, float)):
                    base_pass1 = float(val)
                if base_pass1 is not None:
                    break

    # Structure 2: flat top-level keys
    if plus_pass1 is None:
        for key in ("humaneval_plus_pass1", "humaneval+_pass@1", "plus_pass@1"):
            if key in data:
                plus_pass1 = data[key]
                break

    if base_pass1 is None:
        for key in ("humaneval_base_pass1", "humaneval_pass@1", "base_pass@1"):
            if key in data:
                base_pass1 = data[key]
                break

    # Structure 3: {"pass@1": {"base": ..., "plus": ...}} or similar nested
    if plus_pass1 is None or base_pass1 is None:
        pass_at_1 = data.get("pass@1", {})
        if isinstance(pass_at_1, dict):
            if plus_pass1 is None:
                plus_pass1 = pass_at_1.get("plus") or pass_at_1.get("humaneval_plus")
            if base_pass1 is None:
                base_pass1 = pass_at_1.get("base") or pass_at_1.get("humaneval")

    # Coerce to float
    if plus_pass1 is not None:
        plus_pass1 = float(plus_pass1)
    if base_pass1 is not None:
        base_pass1 = float(base_pass1)

    return plus_pass1, base_pass1


def get_evalplus_version() -> str:
    """Return the installed evalplus version, or 'unknown' if not available."""
    try:
        import evalplus
        return evalplus.__version__
    except Exception:
        return "unknown"


def main():
    parser = argparse.ArgumentParser(
        description="Parse EvalPlus output and extract pass@1 scores"
    )
    parser.add_argument(
        "--results-dir",
        required=True,
        help="Directory containing EvalPlus output (searched recursively for eval_results.json)",
    )
    parser.add_argument(
        "--model",
        required=True,
        help="Model name (used for informational purposes)",
    )
    parser.add_argument(
        "--dataset",
        default="humaneval",
        choices=["humaneval", "mbpp"],
        help="Evaluation dataset (default: humaneval)",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.0,
        help="Temperature used during generation (default: 0.0)",
    )
    parser.add_argument(
        "--num-samples",
        type=int,
        default=1,
        help="Number of samples generated per problem (default: 1)",
    )
    args = parser.parse_args()

    results_dir = Path(args.results_dir)

    if not results_dir.exists():
        print(json.dumps({"error": "Results directory not found"}), file=sys.stderr)
        sys.exit(1)

    eval_results_path = find_eval_results(results_dir)
    if eval_results_path is None:
        print(
            json.dumps({"error": f"eval_results.json not found under {results_dir}"}),
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        with open(eval_results_path) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(
            json.dumps({"error": f"Failed to parse eval_results.json: {e}"}),
            file=sys.stderr,
        )
        sys.exit(1)

    plus_pass1, base_pass1 = extract_pass1(data, args.dataset)

    if plus_pass1 is None:
        print(
            "Warning: humaneval_plus_pass1 not found in eval_results.json",
            file=sys.stderr,
        )
    if base_pass1 is None:
        print(
            "Warning: humaneval_base_pass1 not found in eval_results.json",
            file=sys.stderr,
        )

    output = {
        "humaneval_plus_pass1": plus_pass1,
        "humaneval_base_pass1": base_pass1,
        "eval_framework": "evalplus",
        "eval_framework_version": get_evalplus_version(),
        "eval_dataset": args.dataset,
        "eval_temperature": args.temperature,
        "eval_num_samples": args.num_samples,
    }

    json.dump(output, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
