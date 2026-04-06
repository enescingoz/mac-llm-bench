#!/usr/bin/env bash
# run_bench_mlx.sh — MLX benchmark using mlx_lm.benchmark
# Measures prompt processing and text generation speed at fixed token counts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Find mlx_lm.benchmark
# Checks venv first, then PATH, then common locations
_find_mlx_bench() {
    # Check MLX venv first (recommended install method)
    if [[ -x "$HOME/.venvs/mlx/bin/mlx_lm.benchmark" ]]; then
        echo "$HOME/.venvs/mlx/bin/mlx_lm.benchmark"
        return 0
    fi
    if command -v mlx_lm.benchmark &>/dev/null; then
        echo "mlx_lm.benchmark"
        return 0
    fi
    local search_dirs=(
        "$HOME/.local/bin"
        "$HOME/Library/Python/3.9/bin"
        "$HOME/Library/Python/3.10/bin"
        "$HOME/Library/Python/3.11/bin"
        "$HOME/Library/Python/3.12/bin"
        "$HOME/Library/Python/3.13/bin"
        "/opt/homebrew/bin"
        "/usr/local/bin"
    )
    for dir in "${search_dirs[@]}"; do
        if [[ -x "$dir/mlx_lm.benchmark" ]]; then
            echo "$dir/mlx_lm.benchmark"
            return 0
        fi
    done
    return 1
}

# Run mlx_lm.benchmark for a single prompt/generation size combo
# Outputs: prompt_tps generation_tps peak_memory
run_single_mlx_bench() {
    local mlx_bench="$1"
    local model_repo="$2"
    local prompt_tokens="$3"
    local gen_tokens="$4"
    local num_trials="${5:-5}"

    local output
    output=$("$mlx_bench" --model "$model_repo" -p "$prompt_tokens" -g "$gen_tokens" -n "$num_trials" 2>&1)

    # Parse averages line: "Averages: prompt_tps=X, generation_tps=Y, peak_memory=Z"
    echo "$output" | grep "Averages:" | sed 's/Averages: //' | tr ',' '\n' | tr -d ' '
}

# Run full MLX benchmark suite (same token counts as llama-bench)
run_mlx_benchmark() {
    local model_repo="$1"
    local num_trials="${2:-5}"

    local mlx_bench
    if ! mlx_bench=$(_find_mlx_bench); then
        log_error "mlx_lm.benchmark not found"
        echo "  Install: pip3 install mlx-lm"
        return 1
    fi

    log_info "Running mlx_lm.benchmark..."
    log_info "  Model: $model_repo"
    log_info "  Tests: pp128, pp256, pp512, tg128, tg256"
    log_info "  Trials: $num_trials per config"

    local results="{}"
    local peak_mem="0"

    # Run each config
    for pp in 128 256 512; do
        for tg in 128 256; do
            # Skip pp512+tg256 to save time (optional, remove this to run all)
            if [[ "$pp" == "512" && "$tg" == "256" ]]; then
                continue
            fi

            echo ""
            log_info "  Testing pp${pp} + tg${tg}..."

            local output
            if output=$("$mlx_bench" --model "$model_repo" -p "$pp" -g "$tg" -n "$num_trials" 2>&1); then
                # Parse averages
                local avg_line
                avg_line=$(echo "$output" | grep "Averages:")

                if [[ -n "$avg_line" ]]; then
                    local prompt_tps gen_tps mem
                    prompt_tps=$(echo "$avg_line" | grep -o 'prompt_tps=[0-9.]*' | cut -d= -f2)
                    gen_tps=$(echo "$avg_line" | grep -o 'generation_tps=[0-9.]*' | cut -d= -f2)
                    mem=$(echo "$avg_line" | grep -o 'peak_memory=[0-9.]*' | cut -d= -f2)

                    echo "    prompt: ${prompt_tps} tok/s | generation: ${gen_tps} tok/s | memory: ${mem} GB"

                    # Store results via python
                    results=$(echo "$results" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['pp${pp}'] = round(float('${prompt_tps}'), 2)
d['tg${tg}'] = round(float('${gen_tps}'), 2)
print(json.dumps(d))
" 2>/dev/null || echo "$results")

                    # Track peak memory (highest across configs)
                    if python3 -c "exit(0 if float('${mem}') > float('${peak_mem}') else 1)" 2>/dev/null; then
                        peak_mem="$mem"
                    fi
                fi
            else
                log_warn "  Failed for pp${pp}+tg${tg}"
            fi
        done
    done

    echo ""
    log_ok "Peak memory: ${peak_mem} GB"

    # Return results
    echo "---MLX_RESULTS---"
    echo "SPEED_JSON=$results"
    echo "PEAK_MEM=$peak_mem"
}
