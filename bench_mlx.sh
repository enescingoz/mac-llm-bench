#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Mac LLM Bench (MLX) — Benchmark LLMs using Apple MLX           ║
# ║  Uses mlx_lm.benchmark for standardized speed measurement       ║
# ╚═══════════════════════════════════════════════════════════════════╝

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

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

# Source helpers
source "$LIB_DIR/run_bench_mlx.sh"

# Defaults
ACTION="bench"
MODEL=""
CLEANUP=false
NUM_TRIALS=5

# MLX model mapping: model_id -> mlx-community repo
# Users can also pass a repo directly with --repo
MLX_REPO=""

usage() {
    cat <<'EOF'

  Mac LLM Bench (MLX) — Benchmark LLMs using Apple MLX

  USAGE:
    ./bench_mlx.sh [OPTIONS]

  MODEL SELECTION:
    --model <id>          Model ID from registry (auto-maps to mlx-community repo)
    --repo <repo>         Direct HuggingFace MLX repo (e.g., mlx-community/Qwen3-8B-4bit)

  OPTIONS:
    --trials <n>          Number of benchmark trials (default: 5)
    --cleanup             Delete model cache after benchmarking

  OTHER:
    --hardware            Show detected hardware info
    --results             Show benchmark results
    --help                Show this help

  EXAMPLES:
    ./bench_mlx.sh --repo mlx-community/Qwen3-0.6B-4bit
    ./bench_mlx.sh --repo mlx-community/Gemma-4-E2B-it-4bit
    ./bench_mlx.sh --repo mlx-community/Qwen3-0.6B-4bit --cleanup

EOF
}

# Check dependencies
check_mlx_deps() {
    if ! _find_mlx_bench &>/dev/null; then
        log_error "mlx_lm.benchmark not found"
        echo "  Install: pip3 install mlx-lm"
        return 1
    fi
    if ! command -v python3 &>/dev/null; then
        log_error "python3 not found"
        return 1
    fi
    log_ok "MLX dependencies found"
    return 0
}

# Preflight
preflight() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                 Mac LLM Bench (MLX)                         ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    bash "$LIB_DIR/detect_hardware.sh" --summary
    echo ""
    check_mlx_deps || exit 1
}

# Extract model name from repo (e.g., "mlx-community/Qwen3-8B-4bit" -> "Qwen3-8B")
parse_mlx_repo() {
    local repo="$1"
    local basename
    basename=$(echo "$repo" | sed 's|.*/||')  # Remove org prefix
    echo "$basename"
}

# Benchmark a single MLX model
bench_mlx_model() {
    local repo="$1"
    local model_name
    model_name=$(parse_mlx_repo "$repo")

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Benchmarking (MLX): $model_name"
    echo "  Repo: $repo"
    echo "  Trials: $NUM_TRIALS"
    echo "═══════════════════════════════════════════════════════════════"

    # Run benchmark
    local bench_output
    bench_output=$(run_mlx_benchmark "$repo" "$NUM_TRIALS" 2>&1)

    # Display output (everything before ---MLX_RESULTS---)
    echo "$bench_output" | sed '/---MLX_RESULTS---/,$d'

    # Parse results
    local speed_json peak_mem
    speed_json=$(echo "$bench_output" | grep "SPEED_JSON=" | cut -d= -f2-)
    peak_mem=$(echo "$bench_output" | grep "PEAK_MEM=" | cut -d= -f2-)

    if [[ -z "$speed_json" || "$speed_json" == "{}" ]]; then
        log_error "No benchmark results captured"
        return 1
    fi

    # Get hardware info
    local hw_json
    hw_json=$(bash "$LIB_DIR/detect_hardware.sh" --json)

    # Extract model info from the repo name
    local quant="4bit"
    local params
    params=$(echo "$model_name" | grep -oE '[0-9]+\.?[0-9]*B' | head -1 || echo "?")

    # Save result
    source "$LIB_DIR/collect_results.sh"
    local result_path
    result_path=$(save_result \
        "$hw_json" "$model_name" "$model_name" "$params" "$quant" "$repo" \
        "99" "true" "0" \
        "$speed_json" "$peak_mem" "{}" "mlx" 2>/dev/null) || true

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    log_ok "Complete: $model_name (MLX)"
    if [[ -n "$result_path" ]]; then
        log_ok "Saved: $result_path"
    fi
    echo "═══════════════════════════════════════════════════════════════"

    # Cleanup if requested
    if [[ "$CLEANUP" == "true" ]]; then
        local cache_dir="$HOME/.cache/huggingface/hub"
        local repo_cache
        repo_cache=$(echo "$repo" | tr '/' '--')
        if [[ -d "$cache_dir/models--$repo_cache" ]]; then
            rm -rf "$cache_dir/models--$repo_cache"
            log_ok "Cleaned up MLX model cache"
        fi
    fi
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)    MODEL="$2"; shift 2 ;;
            --repo)     MLX_REPO="$2"; shift 2 ;;
            --trials)   NUM_TRIALS="$2"; shift 2 ;;
            --cleanup)  CLEANUP=true; shift ;;
            --hardware) ACTION="hardware"; shift ;;
            --results)  ACTION="results"; shift ;;
            --help|-h)  usage; exit 0 ;;
            *)
                log_error "Unknown option: $1"
                echo "  Run ./bench_mlx.sh --help for usage"
                exit 1 ;;
        esac
    done
}

# Main
main() {
    parse_args "$@"

    case "$ACTION" in
        hardware)
            bash "$LIB_DIR/detect_hardware.sh" --summary
            ;;
        results)
            source "$LIB_DIR/collect_results.sh"
            print_results_summary
            ;;
        bench)
            if [[ -n "$MLX_REPO" ]]; then
                preflight
                bench_mlx_model "$MLX_REPO"
            elif [[ -n "$MODEL" ]]; then
                log_error "Direct --model mapping not yet implemented. Use --repo with an mlx-community repo."
                echo "  Example: ./bench_mlx.sh --repo mlx-community/Qwen3-8B-4bit"
                exit 1
            else
                usage
                exit 0
            fi
            ;;
    esac
}

main "$@"
