#!/usr/bin/env bash
# run_sweep.sh — Parameter sweep to find optimal configurations
# Tests different combinations of GPU layers, context sizes, batch sizes, etc.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Source helpers
source "$SCRIPT_DIR/run_bench.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    local sweep_mode="${2:-quick}"  # quick or full
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

    # Calculate total combinations
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
    : > "$results_file"  # Clear/create file

    local best_gen_rate=0
    local best_config=""

    for ngl in "${gpu_layers[@]}"; do
        for ctx in "${context_sizes[@]}"; do
            for batch in "${batch_sizes[@]}"; do
                for threads in "${thread_counts[@]}"; do
                    current=$((current + 1))
                    local config="ngl=${ngl} ctx=${ctx} batch=${batch} threads=${threads}"

                    echo -e "${CYAN}[$current/$total]${NC} Testing: $config"

                    # Run a quick bench with the short prompt
                    local result
                    if result=$(run_prompt_bench "$model_path" "$ROOT_DIR/prompts/short.txt" \
                        "$ngl" "$ctx" "$batch" "$threads" "$flash_attention" 128 2>/dev/null); then

                        # Extract generation rate
                        local gen_rate
                        gen_rate=$(echo "$result" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('generation_rate', 0))
except:
    print(0)
" 2>/dev/null || echo "0")

                        local prompt_rate
                        prompt_rate=$(echo "$result" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('prompt_eval_rate', 0))
except:
    print(0)
" 2>/dev/null || echo "0")

                        echo "    → Generation: ${gen_rate} tok/s | Prompt eval: ${prompt_rate} tok/s"

                        # Save to JSONL
                        python3 -c "
import json, sys
result = json.loads('''$result''')
result['parameters'] = {
    'n_gpu_layers': $ngl,
    'context_size': $ctx,
    'batch_size': $batch,
    'threads': $threads,
    'flash_attention': $( [[ "$flash_attention" == "true" ]] && echo "True" || echo "False" )
}
print(json.dumps(result))
" >> "$results_file" 2>/dev/null

                        # Track best config
                        if python3 -c "exit(0 if $gen_rate > $best_gen_rate else 1)" 2>/dev/null; then
                            best_gen_rate="$gen_rate"
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
    echo "  Best generation speed: ${best_gen_rate} tok/s"
    echo "═══════════════════════════════════════════════════"

    # Generate summary
    generate_sweep_summary "$results_file"
}

# Analyze sweep results and find Pareto-optimal configs
generate_sweep_summary() {
    local results_file="$1"

    python3 << 'PYEOF'
import json
import sys

results_file = sys.argv[1] if len(sys.argv) > 1 else ""
if not results_file:
    results_file = """$1"""

results = []
try:
    with open(results_file.strip(), 'r') as f:
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

# Sort by generation rate
results.sort(key=lambda x: x.get('generation_rate', 0), reverse=True)

print("\n  Top 5 Configurations by Generation Speed:")
print("  ─────────────────────────────────────────────")
for i, r in enumerate(results[:5]):
    p = r.get('parameters', {})
    print(f"  {i+1}. {r.get('generation_rate', 0):.1f} tok/s | "
          f"ngl={p.get('n_gpu_layers', '?')} ctx={p.get('context_size', '?')} "
          f"batch={p.get('batch_size', '?')} threads={p.get('threads', '?')}")

# Find Pareto frontier (speed vs context size)
print("\n  Recommended Profiles:")
print("  ─────────────────────────────────────────────")

# Max speed (any context)
if results:
    r = results[0]
    p = r.get('parameters', {})
    print(f"  Max Speed:    {r.get('generation_rate', 0):.1f} tok/s | "
          f"ngl={p.get('n_gpu_layers', '?')} ctx={p.get('context_size', '?')} "
          f"batch={p.get('batch_size', '?')}")

# Best with large context
large_ctx = [r for r in results if r.get('parameters', {}).get('context_size', 0) >= 8192]
if large_ctx:
    r = large_ctx[0]
    p = r.get('parameters', {})
    print(f"  Long Context: {r.get('generation_rate', 0):.1f} tok/s | "
          f"ngl={p.get('n_gpu_layers', '?')} ctx={p.get('context_size', '?')} "
          f"batch={p.get('batch_size', '?')}")

# CPU only (ngl=0)
cpu_only = [r for r in results if r.get('parameters', {}).get('n_gpu_layers', 99) == 0]
if cpu_only:
    r = cpu_only[0]
    p = r.get('parameters', {})
    print(f"  CPU Only:     {r.get('generation_rate', 0):.1f} tok/s | "
          f"ngl=0 ctx={p.get('context_size', '?')} "
          f"batch={p.get('batch_size', '?')}")
PYEOF
}
