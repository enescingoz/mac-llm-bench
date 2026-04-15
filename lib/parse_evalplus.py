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
    """Recursively search for *_eval_results.json under results_dir."""
    for root, _dirs, files in os.walk(results_dir):
        for f in files:
            if f.endswith("_eval_results.json"):
                return Path(root) / f
    # Fallback: exact name
    for root, _dirs, files in os.walk(results_dir):
        if "eval_results.json" in files:
            return Path(root) / "eval_results.json"
    return None


def extract_pass1(data: dict, dataset: str) -> tuple[float | None, float | None]:
    """Extract humaneval_plus_pass1 and humaneval_base_pass1 from eval_results data.

    EvalPlus v0.3.x stores per-task results in {"eval": {"HumanEval/0": [{...}], ...}}
    with base_status and plus_status fields. We compute pass@1 from these.
    Also tries summary-based structures for forward compatibility.
    Returns (plus_pass1, base_pass1).
    """
    plus_pass1 = None
    base_pass1 = None

    eval_section = data.get("eval", {})

    # Structure 1 (EvalPlus v0.3.x): per-task results with base_status/plus_status
    # {"eval": {"HumanEval/0": [{"base_status": "pass", "plus_status": "pass", ...}], ...}}
    if eval_section:
        first_val = next(iter(eval_section.values()), None)
        if isinstance(first_val, list) and first_val and isinstance(first_val[0], dict):
            if "base_status" in first_val[0] or "plus_status" in first_val[0]:
                total = 0
                base_passed = 0
                plus_passed = 0
                for task_results in eval_section.values():
                    for result in task_results:
                        total += 1
                        if result.get("base_status") == "pass":
                            base_passed += 1
                        if result.get("plus_status") == "pass":
                            plus_passed += 1
                if total > 0:
                    base_pass1 = base_passed / total
                    plus_pass1 = plus_passed / total

    # Structure 2 (summary format): {"eval": {"humaneval_plus": {"pass@1": 0.84}, ...}}
    if plus_pass1 is None and eval_section:
        for plus_key in ("humaneval_plus", "humaneval+", "plus"):
            if plus_key in eval_section:
                val = eval_section[plus_key]
                if isinstance(val, dict):
                    plus_pass1 = val.get("pass@1") or val.get("pass_at_1")
                elif isinstance(val, (int, float)):
                    plus_pass1 = float(val)
                if plus_pass1 is not None:
                    break

    if base_pass1 is None and eval_section:
        for base_key in ("humaneval", "base"):
            if base_key in eval_section:
                val = eval_section[base_key]
                if isinstance(val, dict):
                    base_pass1 = val.get("pass@1") or val.get("pass_at_1")
                elif isinstance(val, (int, float)):
                    base_pass1 = float(val)
                if base_pass1 is not None:
                    break

    # Coerce to float and round
    if plus_pass1 is not None:
        plus_pass1 = round(float(plus_pass1), 4)
    if base_pass1 is not None:
        base_pass1 = round(float(base_pass1), 4)

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
