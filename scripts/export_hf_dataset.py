#!/usr/bin/env python3
"""Export benchmark result JSONs to a single Parquet (or CSV) file for HuggingFace dataset publishing.

Usage:
    python3 scripts/export_hf_dataset.py [--output-dir dataset/] [--format parquet|csv]

Default output: dataset/results.parquet
"""

import argparse
import json
import os
import glob
import sys

RESULTS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "results")

GENERATIONS = ["m1", "m2", "m3", "m4", "m5"]
VARIANTS = ["base", "pro", "max", "ultra"]


def _safe_float(value):
    """Convert value to float, returning None on failure."""
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _safe_int(value):
    """Convert value to int, returning None on failure."""
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def flatten_result(data, source_path):
    """Flatten a result dict into a single row dict matching the column schema.

    Missing fields become None (null in Parquet/CSV).
    """
    model = data.get("model", {})
    hw = data.get("hardware", {})
    runtime = data.get("runtime", {})
    speed = data.get("speed", {})
    memory = data.get("memory", {})
    quality = data.get("quality", {})

    # Derive model_id from filename if not present in JSON
    model_id = model.get("id")
    if not model_id:
        basename = os.path.basename(source_path)
        model_id = os.path.splitext(basename)[0]

    return {
        "model_name": model.get("name"),
        "model_id": model_id,
        "params": model.get("params"),
        "quant": model.get("quant"),
        "runtime": runtime.get("name"),
        "chip": hw.get("chip"),
        "cpu_cores": _safe_int(hw.get("cpu_cores")),
        "gpu_cores": _safe_int(hw.get("gpu_cores")),   # schema says string; coerce to int
        "ram_gb": _safe_int(hw.get("total_ram_gb")),
        "os_version": hw.get("os_version"),
        "pp128_toks": _safe_float(speed.get("pp128")),
        "pp256_toks": _safe_float(speed.get("pp256")),
        "pp512_toks": _safe_float(speed.get("pp512")),
        "tg128_toks": _safe_float(speed.get("tg128")),
        "tg256_toks": _safe_float(speed.get("tg256")),
        "peak_memory_gb": _safe_float(memory.get("peak_rss_gb")),
        "humaneval_plus_pass1": _safe_float(quality.get("humaneval_plus_pass1")),
        "humaneval_base_pass1": _safe_float(quality.get("humaneval_base_pass1")),
        "perplexity": _safe_float(quality.get("perplexity")),
        "eval_framework_version": quality.get("eval_framework_version"),
        "timestamp": data.get("timestamp"),
    }


def collect_json_files():
    """Recursively scan results/ for all .json files, mirroring generate_results.py's walk."""
    json_files = []
    for gen in GENERATIONS:
        for variant in VARIANTS:
            raw_dir = os.path.join(RESULTS_DIR, gen, variant, "raw")
            if not os.path.isdir(raw_dir):
                continue
            for chip_dir in sorted(glob.glob(os.path.join(raw_dir, "*"))):
                if not os.path.isdir(chip_dir):
                    continue
                for runtime_dir in sorted(glob.glob(os.path.join(chip_dir, "*"))):
                    if not os.path.isdir(runtime_dir):
                        continue
                    for json_file in sorted(glob.glob(os.path.join(runtime_dir, "*.json"))):
                        json_files.append(json_file)
    return json_files


def load_rows(json_files):
    """Load and flatten all JSON files into a list of row dicts.

    Returns (rows, skipped_count).
    """
    rows = []
    skipped = 0
    for path in json_files:
        try:
            with open(path) as f:
                data = json.load(f)
            rows.append(flatten_result(data, path))
        except (json.JSONDecodeError, IOError) as exc:
            print(f"  WARNING: skipping {path}: {exc}", file=sys.stderr)
            skipped += 1
    return rows, skipped


def write_parquet(rows, output_path):
    """Write rows to a Parquet file using pandas + pyarrow."""
    import pandas as pd  # noqa: PLC0415

    df = pd.DataFrame(rows)

    # Enforce column dtypes where possible
    int_cols = ["cpu_cores", "gpu_cores", "ram_gb"]
    float_cols = [
        "pp128_toks", "pp256_toks", "pp512_toks",
        "tg128_toks", "tg256_toks", "peak_memory_gb",
        "humaneval_plus_pass1", "humaneval_base_pass1", "perplexity",
    ]
    for col in int_cols:
        if col in df.columns:
            df[col] = pd.array(df[col], dtype=pd.Int64Dtype())
    for col in float_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    df.to_parquet(output_path, index=False)


def write_csv(rows, output_path):
    """Write rows to a CSV file using the stdlib csv module."""
    import csv  # noqa: PLC0415

    if not rows:
        print("No rows to write.")
        return

    columns = list(rows[0].keys())
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(
        description="Export benchmark results to a HuggingFace-compatible Parquet/CSV dataset."
    )
    parser.add_argument(
        "--output-dir",
        default="dataset",
        metavar="DIR",
        help="Output directory (default: dataset/)",
    )
    parser.add_argument(
        "--format",
        choices=["parquet", "csv"],
        default="parquet",
        help="Output format: parquet (default) or csv",
    )
    args = parser.parse_args()

    # Resolve output path relative to repo root (same as RESULTS_DIR parent)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_dir = os.path.join(repo_root, args.output_dir)
    ext = "parquet" if args.format == "parquet" else "csv"
    output_path = os.path.join(output_dir, f"results.{ext}")

    print("Scanning results/...")
    json_files = collect_json_files()
    print(f"  Found {len(json_files)} JSON file(s)")

    print("Loading and flattening results...")
    rows, skipped = load_rows(json_files)
    processed = len(rows)
    print(f"  Processed: {processed}  Skipped: {skipped}")

    if not rows:
        print("No rows to export. Exiting.")
        sys.exit(0)

    os.makedirs(output_dir, exist_ok=True)

    if args.format == "parquet":
        try:
            write_parquet(rows, output_path)
        except ImportError:
            print(
                "WARNING: pandas or pyarrow not installed. Falling back to CSV.",
                file=sys.stderr,
            )
            output_path = os.path.join(output_dir, "results.csv")
            write_csv(rows, output_path)
    else:
        write_csv(rows, output_path)

    print(f"\nExported {processed} row(s) -> {output_path}")


if __name__ == "__main__":
    main()
