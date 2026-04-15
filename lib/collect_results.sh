#!/usr/bin/env bash
# collect_results.sh — Save and display benchmark results (v2 schema)
# Results stored in: results/{generation}/raw/{chip}_{cpu}c-{gpu}g_{ram}gb/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }

# Build folder path from hardware info
# Format: results/{generation}/raw/{chip}_{cpu}c-{gpu}g_{ram}gb/
get_result_dir() {
    local chip="$1"       # e.g., "Apple M5" or "Apple M4 Pro"
    local cpu_cores="$2"
    local gpu_cores="$3"
    local ram_gb="$4"

    # Parse generation and variant from chip name
    # "Apple M5" -> generation=m5, variant=base
    # "Apple M4 Pro" -> generation=m4, variant=pro
    local cleaned
    cleaned=$(echo "$chip" | sed 's/Apple //i' | tr '[:upper:]' '[:lower:]')

    local generation variant folder_name
    if echo "$cleaned" | grep -qE '(pro|max|ultra)'; then
        generation=$(echo "$cleaned" | awk '{print $1}')
        variant=$(echo "$cleaned" | awk '{print $2}')
        folder_name="${generation}-${variant}_${cpu_cores}c-${gpu_cores}g_${ram_gb}gb"
    else
        generation=$(echo "$cleaned" | awk '{print $1}')
        folder_name="${generation}_${cpu_cores}c-${gpu_cores}g_${ram_gb}gb"
    fi

    echo "$ROOT_DIR/results/$generation/raw/$folder_name"
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
    local runtime="${13:-gguf}"

    python3 << PYEOF
import json, os, re
from datetime import datetime, timezone

hw = json.loads('''$hw_json''')

# Parse speed data from llama-bench JSON output
speed_raw = '''$speed_json'''
speed = {}
try:
    bench_results = json.loads(speed_raw)
    if isinstance(bench_results, list):
        for r in bench_results:
            n_prompt = r.get("n_prompt", 0)
            n_gen = r.get("n_gen", 0)
            avg_ts = r.get("avg_ts", 0)
            if n_prompt > 0 and avg_ts:
                speed[f"pp{n_prompt}"] = round(float(avg_ts), 2)
            elif n_gen > 0 and avg_ts:
                speed[f"tg{n_gen}"] = round(float(avg_ts), 2)
    elif isinstance(bench_results, dict):
        speed = bench_results
except:
    pass

quality = {}
try:
    quality = json.loads('''$quality_json''')
except:
    pass

# Get file size (MLX uses HF repo strings, not local paths)
import subprocess
file_size_gb = 0
model_path = "$model_path"
runtime = "$runtime"
if runtime != "mlx" and os.path.exists(model_path):
    file_size_gb = round(os.path.getsize(model_path) / 1073741824, 2)

# Get runtime name and version
if runtime == "mlx":
    runtime_name = "mlx-lm"
    try:
        version = subprocess.check_output(
            ["python3", "-c", "import mlx_lm; print(mlx_lm.__version__)"],
            stderr=subprocess.STDOUT, text=True).strip()
    except:
        version = "unknown"
else:
    runtime_name = "llama.cpp"
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
        "name": runtime_name,
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

# Determine output directory using chip info
chip = hw.get("chip", "unknown")
cpu_cores = hw.get("cpu_cores", 0)
gpu_cores = hw.get("gpu_cores", "0")
ram_gb = hw.get("total_ram_gb", 0)

# Parse generation and variant
cleaned = re.sub(r'(?i)apple\s*', '', chip).strip().lower()
parts = cleaned.split()
generation = parts[0] if parts else "unknown"
variant = parts[1] if len(parts) > 1 else "base"

if variant and variant != "base":
    folder_name = f"{generation}-{variant}_{cpu_cores}c-{gpu_cores}g_{ram_gb}gb"
else:
    variant = "base"
    folder_name = f"{generation}_{cpu_cores}c-{gpu_cores}g_{ram_gb}gb"

output_dir = os.path.join("$ROOT_DIR", "results", generation, variant, "raw", folder_name, "$runtime")
os.makedirs(output_dir, exist_ok=True)

filename = f"${model_id}_${quant}_ngl${n_gpu_layers}.json"
filepath = os.path.join(output_dir, filename)

with open(filepath, "w") as f:
    json.dump(result, f, indent=2)

print(filepath)
PYEOF
}

# Print summary table from all results
print_results_summary() {
    python3 - "$ROOT_DIR" << 'PYEOF'
import json, os, glob, sys

root_dir = sys.argv[1] if len(sys.argv) > 1 else "."
results_dir = os.path.join(root_dir, "results")

all_results = []
for fp in glob.glob(os.path.join(results_dir, "**", "*.json"), recursive=True):
    try:
        with open(fp) as f:
            all_results.append(json.load(f))
    except:
        continue

if not all_results:
    print("  No results found. Run ./bench_gguf.sh --model <id> or ./bench_mlx.sh --model <id>")
    sys.exit(0)

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
