#!/usr/bin/env bash
# run_sweep.sh — Parameter sweep using llama-bench to find optimal configurations
# Tests different combinations of GPU layers, context sizes, batch sizes, etc.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default sweep configurations
DEFAULT_GPU_LAYERS=(0 16 32 99)
DEFAULT_CONTEXT_SIZES=(512 2048 4096 8192)
DEFAULT_BATCH_SIZES=(128 256 512 1024)
DEFAULT_THREAD_COUNTS=(0 4 8)  # 0 = auto

# Quick sweep (fewer combinations)
QUICK_GPU_LAYERS=(0 99)
QUICK_CONTEXT_SIZES=(2048 8192)
QUICK_BATCH_SIZES=(512)
QUICK_THREAD_COUNTS=(0)

run_parameter_sweep() {
    local model_path="$1"
    local sweep_mode="${2:-quick}"
    local output_dir="${3:-$ROOT_DIR/results/sweeps}"
    local flash_attention="${4:-true}"

    local model_name
    model_name=$(basename "$model_path" .gguf)

    # Select sweep parameters
    local -a gpu_layers context_sizes batch_sizes thread_counts
    if [[ "$sweep_mode" == "full" ]]; then
        gpu_layers=("${DEFAULT_GPU_LAYERS[@]}")
        context_sizes=("${DEFAULT_CONTEXT_SIZES[@]}")
        batch_sizes=("${DEFAULT_BATCH_SIZES[@]}")
        thread_counts=("${DEFAULT_THREAD_COUNTS[@]}")
    else
        gpu_layers=("${QUICK_GPU_LAYERS[@]}")
        context_sizes=("${QUICK_CONTEXT_SIZES[@]}")
        batch_sizes=("${QUICK_BATCH_SIZES[@]}")
        thread_counts=("${QUICK_THREAD_COUNTS[@]}")
    fi

    local total=$(( ${#gpu_layers[@]} * ${#context_sizes[@]} * ${#batch_sizes[@]} * ${#thread_counts[@]} ))
    local current=0

    echo "═══════════════════════════════════════════════════"
    echo "  Parameter Sweep: $model_name"
    echo "  Mode: $sweep_mode ($total combinations)"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "  GPU Layers:    ${gpu_layers[*]}"
    echo "  Context Sizes: ${context_sizes[*]}"
    echo "  Batch Sizes:   ${batch_sizes[*]}"
    echo "  Thread Counts: ${thread_counts[*]} (0=auto)"
    echo "  Flash Attn:    $flash_attention"
    echo ""

    mkdir -p "$output_dir"

    local results_file="$output_dir/${model_name}_sweep.jsonl"
    : > "$results_file"

    local best_tg_rate=0
    local best_config=""

    for ngl in "${gpu_layers[@]}"; do
        for ctx in "${context_sizes[@]}"; do
            for batch in "${batch_sizes[@]}"; do
                for threads in "${thread_counts[@]}"; do
                    current=$((current + 1))
                    local config="ngl=${ngl} ctx=${ctx} batch=${batch} threads=${threads}"

                    echo -e "${CYAN}[$current/$total]${NC} Testing: $config"

                    # Build llama-bench args — quick test: pp128 + tg128 only
                    local args=(-m "$model_path" -ngl "$ngl" -p 128 -n 128)

                    if [[ "$flash_attention" == "true" ]]; then
                        args+=(-fa 1)
                    fi
                    if [[ "$threads" -gt 0 ]]; then
                        args+=(-t "$threads")
                    fi

                    # Run llama-bench with JSON output
                    local json_output
                    if json_output=$(llama-bench "${args[@]}" -o json 2>/dev/null); then
                        # Parse results
                        local rates
                        rates=$(echo "$json_output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
pp = tg = 0
for r in data:
    if r.get('n_prompt', 0) > 0: pp = r.get('avg_ts', 0)
    if r.get('n_gen', 0) > 0: tg = r.get('avg_ts', 0)
print(f'{pp:.1f} {tg:.1f}')
" 2>/dev/null || echo "0 0")

                        local pp_rate tg_rate
                        pp_rate=$(echo "$rates" | awk '{print $1}')
                        tg_rate=$(echo "$rates" | awk '{print $2}')

                        echo "    → tg128: ${tg_rate} tok/s | pp128: ${pp_rate} tok/s"

                        # Save to JSONL
                        echo "$json_output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
entry = {
    'parameters': {
        'n_gpu_layers': $ngl, 'context_size': $ctx,
        'batch_size': $batch, 'threads': $threads,
        'flash_attention': $( [[ "$flash_attention" == "true" ]] && echo "True" || echo "False" )
    },
    'speed': {}
}
for r in data:
    if r.get('n_prompt', 0) > 0: entry['speed']['pp128'] = round(r['avg_ts'], 2)
    if r.get('n_gen', 0) > 0: entry['speed']['tg128'] = round(r['avg_ts'], 2)
print(json.dumps(entry))
" >> "$results_file" 2>/dev/null

                        # Track best
                        if python3 -c "exit(0 if $tg_rate > $best_tg_rate else 1)" 2>/dev/null; then
                            best_tg_rate="$tg_rate"
                            best_config="$config"
                        fi
                    else
                        echo -e "    → ${RED}Failed${NC} (may need more RAM or smaller context)"
                    fi
                done
            done
        done
    done

    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Sweep Complete"
    echo "═══════════════════════════════════════════════════"
    echo "  Results: $results_file"
    echo "  Best config: $best_config"
    echo "  Best tg128 speed: ${best_tg_rate} tok/s"
    echo "═══════════════════════════════════════════════════"

    generate_sweep_summary "$results_file"
}

generate_sweep_summary() {
    local results_file="$1"

    python3 - "$results_file" << 'PYEOF'
import json, sys

results_file = sys.argv[1]
results = []
try:
    with open(results_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                results.append(json.loads(line))
except FileNotFoundError:
    print("No results file found")
    sys.exit(1)

if not results:
    print("No results to analyze")
    sys.exit(0)

results.sort(key=lambda x: x.get('speed', {}).get('tg128', 0), reverse=True)

print("\n  Top 5 Configurations by tg128 Speed:")
print("  ─────────────────────────────────────────────")
for i, r in enumerate(results[:5]):
    p = r.get('parameters', {})
    s = r.get('speed', {})
    print(f"  {i+1}. tg128={s.get('tg128', 0):.1f} tok/s  pp128={s.get('pp128', 0):.1f} tok/s | "
          f"ngl={p.get('n_gpu_layers', '?')} ctx={p.get('context_size', '?')} "
          f"batch={p.get('batch_size', '?')} threads={p.get('threads', '?')}")

print("\n  Recommended Profiles:")
print("  ─────────────────────────────────────────────")

if results:
    r = results[0]
    p = r.get('parameters', {})
    s = r.get('speed', {})
    print(f"  Max Speed:    tg128={s.get('tg128', 0):.1f} tok/s | "
          f"ngl={p.get('n_gpu_layers', '?')} ctx={p.get('context_size', '?')} "
          f"batch={p.get('batch_size', '?')}")

large_ctx = [r for r in results if r.get('parameters', {}).get('context_size', 0) >= 8192]
if large_ctx:
    r = large_ctx[0]
    p = r.get('parameters', {})
    s = r.get('speed', {})
    print(f"  Long Context: tg128={s.get('tg128', 0):.1f} tok/s | "
          f"ngl={p.get('n_gpu_layers', '?')} ctx={p.get('context_size', '?')} "
          f"batch={p.get('batch_size', '?')}")

cpu_only = [r for r in results if r.get('parameters', {}).get('n_gpu_layers', 99) == 0]
if cpu_only:
    r = cpu_only[0]
    p = r.get('parameters', {})
    s = r.get('speed', {})
    print(f"  CPU Only:     tg128={s.get('tg128', 0):.1f} tok/s | "
          f"ngl=0 ctx={p.get('context_size', '?')} "
          f"batch={p.get('batch_size', '?')}")
PYEOF
}
