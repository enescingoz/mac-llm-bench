#!/usr/bin/env bash
# collect_results.sh — Save and display benchmark results (v2 schema)
# Results are JSON files organized by hardware and model.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }

# Generate sanitized directory name from hardware
get_hardware_dir_name() {
    local chip="$1"
    local ram="$2"
    local machine="$3"
    local name="$machine $chip ${ram}GB"
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

# Save a benchmark result as JSON
save_result() {
    local hw_json="$1"
    local model_id="$2"
    local model_name="$3"
    local model_params="$4"
    local quant="$5"
    local model_path="$6"
    local n_gpu_layers="$7"
    local flash_attention="$8"
    local threads="$9"
    local speed_json="${10}"
    local peak_mem="${11}"
    local quality_json="${12:-{}}"
    local raw_output="${13:-}"

    python3 << PYEOF
import json, os
from datetime import datetime, timezone

hw = json.loads('''$hw_json''')

# Parse speed data from llama-bench JSON output
speed_raw = '''$speed_json'''
speed = {}
try:
    bench_results = json.loads(speed_raw)
    if isinstance(bench_results, list):
        for r in bench_results:
            test = r.get("test", "")
            tps = r.get("t/s", 0)
            if test and tps:
                speed[test] = round(float(tps), 2)
    elif isinstance(bench_results, dict):
        speed = bench_results
except:
    pass

quality = {}
try:
    quality = json.loads('''$quality_json''')
except:
    pass

# Get file size
file_size_gb = 0
model_path = "$model_path"
if os.path.exists(model_path):
    file_size_gb = round(os.path.getsize(model_path) / 1073741824, 2)

# Get llama.cpp version
import subprocess
try:
    version = subprocess.check_output(["llama-bench", "--version"], stderr=subprocess.STDOUT, text=True).strip().split("\n")[0]
except:
    version = "unknown"

result = {
    "version": "2.0",
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hardware": hw,
    "model": {
        "name": "$model_name",
        "id": "$model_id",
        "params": "$model_params",
        "quant": "$quant",
        "file_size_gb": file_size_gb
    },
    "runtime": {
        "name": "llama.cpp",
        "version": version
    },
    "parameters": {
        "n_gpu_layers": $n_gpu_layers,
        "flash_attention": $( [[ "$flash_attention" == "true" ]] && echo "True" || echo "False" ),
        "threads": $threads
    },
    "speed": speed,
    "memory": {
        "peak_rss_gb": float("$peak_mem") if "$peak_mem" else 0
    }
}

if quality:
    result["quality"] = quality

raw = """$raw_output"""
if raw:
    result["llama_bench_raw"] = raw

# Save to file
hw_dir = "$( get_hardware_dir_name "${HW_CHIP:-unknown}" "${HW_TOTAL_RAM_GB:-0}" "${HW_MAC_MODEL:-unknown}" )"
output_dir = os.path.join("$ROOT_DIR", "results", hw_dir, "$model_id")
os.makedirs(output_dir, exist_ok=True)

filename = f"${model_id}_${quant}_ngl${n_gpu_layers}.json"
filepath = os.path.join(output_dir, filename)

with open(filepath, "w") as f:
    json.dump(result, f, indent=2)

print(filepath)
PYEOF
}

# Print summary table
print_results_summary() {
    python3 << 'PYEOF'
import json, os, glob

results_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "results")
if not os.path.exists(results_dir):
    results_dir = "results"

all_results = []
for fp in glob.glob(os.path.join(results_dir, "**", "*.json"), recursive=True):
    if "schema" in fp or "sweep" in fp:
        continue
    try:
        with open(fp) as f:
            all_results.append(json.load(f))
    except:
        continue

if not all_results:
    print("  No results found. Run ./bench.sh --model <id> to generate benchmarks.")
    return

by_hw = {}
for r in all_results:
    hw = r.get("hardware", {})
    key = f"{hw.get('chip', '?')} ({hw.get('total_ram_gb', '?')}GB)"
    by_hw.setdefault(key, []).append(r)

for hw_name, results in sorted(by_hw.items()):
    print(f"\n  {hw_name}")
    print(f"  {'─' * 75}")
    print(f"  {'Model':<25} {'Quant':<8} {'pp256':>10} {'tg128':>10} {'Memory':>10}")
    print(f"  {'':25} {'':8} {'tok/s':>10} {'tok/s':>10} {'GB':>10}")
    print(f"  {'─' * 75}")

    results.sort(key=lambda x: x.get("speed", {}).get("tg128", 0), reverse=True)
    for r in results:
        m = r.get("model", {})
        s = r.get("speed", {})
        mem = r.get("memory", {})
        print(f"  {m.get('name', '?'):<25} {m.get('quant', '?'):<8} "
              f"{s.get('pp256', 0):>10.1f} {s.get('tg128', 0):>10.1f} "
              f"{mem.get('peak_rss_gb', 0):>10.1f}")

PYEOF
}
