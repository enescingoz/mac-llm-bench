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
TAG=""
CLEANUP=false
NUM_TRIALS=5

# MLX model mapping: model_id -> mlx-community repo
# Users can also pass a repo directly with --repo
MLX_REPO=""

# Hardware vars (populated by load_hardware)
HW_TOTAL_RAM_GB=0

usage() {
    cat <<'EOF'

  Mac LLM Bench (MLX) — Benchmark LLMs using Apple MLX

  USAGE:
    ./bench_mlx.sh [OPTIONS]

  MODEL SELECTION:
    --model <id>          Model ID from registry (auto-maps to mlx-community repo)
    --repo <repo>         Direct HuggingFace MLX repo (e.g., mlx-community/Qwen3-8B-4bit)
    --all                 Benchmark all models with MLX sources in the registry
    --auto                Benchmark all MLX models that fit in your RAM
    --tag <tag>           Benchmark MLX models with a specific tag

  OPTIONS:
    --trials <n>          Number of benchmark trials (default: 5)
    --cleanup             Delete model cache after benchmarking

  OTHER:
    --hardware            Show detected hardware info
    --results             Show benchmark results
    --help                Show this help

  EXAMPLES:
    ./bench_mlx.sh --model qwen3-8b
    ./bench_mlx.sh --repo mlx-community/Qwen3-0.6B-4bit
    ./bench_mlx.sh --auto
    ./bench_mlx.sh --tag coding --cleanup

EOF
}

# ─── Parse YAML ────────────────────────────────────────────────────
parse_models() {
    python3 "$LIB_DIR/parse_yaml.py" "$SCRIPT_DIR/models.yaml" 2>/dev/null
}

# ─── Detect hardware ──────────────────────────────────────────────
load_hardware() {
    eval "$(bash "$LIB_DIR/detect_hardware.sh" --shell)"
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
    load_hardware

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                 Mac LLM Bench (MLX)                         ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    bash "$LIB_DIR/detect_hardware.sh" --summary
    echo ""

    # Check if project venv exists but is not activated
    if [[ -f "$SCRIPT_DIR/.venv/bin/activate" ]] && [[ -z "${VIRTUAL_ENV:-}" ]]; then
        log_warn "Project .venv found but not activated. Run: source .venv/bin/activate"
    fi

    check_mlx_deps || exit 1
}

# Extract model name from repo (e.g., "mlx-community/Qwen3-8B-4bit" -> "Qwen3-8B-4bit")
parse_mlx_repo() {
    local repo="$1"
    local basename
    basename=$(echo "$repo" | sed 's|.*/||')  # Remove org prefix
    echo "$basename"
}

# ─── Get model info by ID ──────────────────────────────────────────
get_model_info() {
    local model_id="$1"
    python3 -c "
import json, sys
data = json.loads('''$(parse_models)''')
models = data.get('models', {})
m = models.get('$model_id')
if m:
    m['id'] = '$model_id'
    print(json.dumps(m))
else:
    print('{}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

# ─── Get MLX model info (repo, model_name, params) by ID ──────────
# Returns: repo|model_name|model_params|min_ram
get_mlx_model_info() {
    local model_id="$1"
    python3 -c "
import json, sys
data = json.loads('''$(parse_models)''')
models = data.get('models', {})
m = models.get('$model_id')
if not m:
    print('ERROR:Model not found', file=sys.stderr)
    sys.exit(1)
mlx = m.get('mlx_sources', [])
if not mlx:
    print('ERROR:No MLX mapping', file=sys.stderr)
    sys.exit(1)
repo = mlx[0].get('repo', '')
name = m.get('name', '$model_id')
params = m.get('params', '?')
min_ram = m.get('min_ram', 0)
print(f'{repo}|{name}|{params}|{min_ram}')
" 2>/dev/null
}

# ─── Get list of MLX-capable models to benchmark ──────────────────
get_mlx_models_to_bench() {
    local filter="$1"

    python3 -c "
import json
data = json.loads('''$(parse_models)''')
models = data.get('models', {})

for mid, m in sorted(models.items()):
    # Only include models with mlx_sources
    mlx = m.get('mlx_sources', [])
    if not mlx:
        continue

    min_ram = m.get('min_ram', 0)
    tags = m.get('tags', [])
    if isinstance(tags, str): tags = [tags]

    if '$filter' == 'auto' and min_ram > $HW_TOTAL_RAM_GB: continue
    if '$filter'.startswith('tag:'):
        if '$filter'.split(':',1)[1] not in tags: continue

    print(mid)
" 2>/dev/null
}

# ─── Show plan for MLX batch benchmarks ───────────────────────────
show_mlx_plan() {
    local model_ids=("$@")

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  MLX Benchmark Plan"
    echo "═══════════════════════════════════════════════════════════════"
    printf "\n  %-20s %-8s %-10s %s\n" "Model" "Params" "Min RAM" "MLX Repo"
    echo "  ─────────────────────────────────────────────────────────────"

    for model_id in "${model_ids[@]}"; do
        local info
        info=$(get_mlx_model_info "$model_id" 2>/dev/null || echo "")
        if [[ -z "$info" ]]; then continue; fi

        local repo model_name params min_ram
        IFS='|' read -r repo model_name params min_ram <<< "$info"

        printf "  %-20s %-8s %-10s %s\n" "$model_id" "$params" "${min_ram}GB" "$repo"
    done

    echo ""
    echo "  System RAM: ${HW_TOTAL_RAM_GB}GB"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    if [[ -t 0 ]]; then
        read -rp "  Proceed? [Y/n]: " choice
        [[ "$choice" =~ [Nn] ]] && exit 0
    fi
}

# Benchmark a single MLX model
# Usage: bench_mlx_model <repo> [model_id] [model_name] [model_params]
bench_mlx_model() {
    local repo="$1"
    local model_id="${2:-}"
    local model_name="${3:-}"
    local model_params="${4:-}"

    # Fallback to parsing from repo name if not provided
    if [[ -z "$model_name" ]]; then
        model_name=$(parse_mlx_repo "$repo")
    fi
    if [[ -z "$model_id" ]]; then
        model_id=$(parse_mlx_repo "$repo")
    fi
    if [[ -z "$model_params" ]]; then
        model_params=$(echo "$model_name" | grep -oE '[0-9]+\.?[0-9]*B' | head -1 || echo "?")
    fi

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

    local quant="4bit"

    # Save result
    source "$LIB_DIR/collect_results.sh"
    local result_path
    result_path=$(save_result \
        "$hw_json" "$model_id" "$model_name" "$model_params" "$quant" "$repo" \
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

# ─── Run benchmarks for a list of model IDs ──────────────────────
run_mlx_benchmarks() {
    local model_ids=("$@")

    for model_id in "${model_ids[@]}"; do
        local info
        info=$(get_mlx_model_info "$model_id" 2>/dev/null || echo "")
        if [[ -z "$info" ]]; then
            log_error "Could not get MLX info for $model_id, skipping"
            continue
        fi

        local repo model_name model_params min_ram
        IFS='|' read -r repo model_name model_params min_ram <<< "$info"

        # RAM check
        if (( min_ram > HW_TOTAL_RAM_GB )); then
            log_warn "$model_id needs ${min_ram}GB RAM, you have ${HW_TOTAL_RAM_GB}GB"
            if [[ -t 0 ]]; then
                read -rp "  [S]kip / [F]orce / [Q]uit: " choice
                case "$choice" in
                    [Ss]) continue ;; [Qq]) exit 0 ;;
                esac
            else
                log_warn "Skipping $model_id (non-interactive mode)"
                continue
            fi
        fi

        bench_mlx_model "$repo" "$model_id" "$model_name" "$model_params"
    done
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)    MODEL="$2"; shift 2 ;;
            --repo)     MLX_REPO="$2"; shift 2 ;;
            --all)      ACTION="bench_all"; shift ;;
            --auto)     ACTION="bench_auto"; shift ;;
            --tag)      TAG="$2"; ACTION="bench_tag"; shift 2 ;;
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
        bench_all)
            preflight
            local -a models=()
            while IFS= read -r line; do models+=("$line"); done < <(get_mlx_models_to_bench "all")
            [[ ${#models[@]} -eq 0 ]] && { log_error "No models with mlx_sources found in registry"; exit 1; }
            show_mlx_plan "${models[@]}"
            run_mlx_benchmarks "${models[@]}"
            ;;
        bench_auto)
            preflight
            local -a models=()
            while IFS= read -r line; do models+=("$line"); done < <(get_mlx_models_to_bench "auto")
            [[ ${#models[@]} -eq 0 ]] && { log_error "No MLX models fit in ${HW_TOTAL_RAM_GB}GB RAM"; exit 1; }
            show_mlx_plan "${models[@]}"
            run_mlx_benchmarks "${models[@]}"
            ;;
        bench_tag)
            preflight
            local -a models=()
            while IFS= read -r line; do models+=("$line"); done < <(get_mlx_models_to_bench "tag:$TAG")
            [[ ${#models[@]} -eq 0 ]] && { log_error "No MLX models with tag '$TAG'"; exit 1; }
            show_mlx_plan "${models[@]}"
            run_mlx_benchmarks "${models[@]}"
            ;;
        bench)
            if [[ -n "$MLX_REPO" ]]; then
                preflight
                bench_mlx_model "$MLX_REPO"
            elif [[ -n "$MODEL" ]]; then
                preflight
                local info
                info=$(get_mlx_model_info "$MODEL" 2>/dev/null || echo "")
                if [[ -z "$info" ]]; then
                    log_error "No MLX mapping for '$MODEL'. Add mlx_sources to models.yaml or use --repo directly."
                    exit 1
                fi
                local repo model_name model_params min_ram
                IFS='|' read -r repo model_name model_params min_ram <<< "$info"
                bench_mlx_model "$repo" "$MODEL" "$model_name" "$model_params"
            else
                usage
                exit 0
            fi
            ;;
    esac
}

main "$@"
