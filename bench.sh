#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Mac LLM Bench — Benchmark LLMs on Apple Silicon                ║
# ║  Core benchmark: llama-bench (standardized, content-agnostic)   ║
# ║  Optional quality: llama-perplexity on WikiText-2               ║
# ╚═══════════════════════════════════════════════════════════════════╝

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# ─── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Defaults ──────────────────────────────────────────────────────
ACTION="bench"
MODEL=""
QUANT=""
TAG=""
MAX_PARAMS=""
CUSTOM_REPO=""
MODEL_PATH=""
N_GPU_LAYERS=99
THREADS=0
FLASH_ATTENTION=true
CLEANUP=false
STREAMING=false
SWEEP_MODE=""
RUN_QUALITY=false
CACHE_DIR="${MAC_LLM_CACHE_DIR:-$HOME/.cache/mac-llm-bench}"

# Hardware vars (populated by detect_hardware)
HW_MAC_MODEL=""
HW_CHIP=""
HW_TOTAL_RAM_GB=0
HW_CPU_CORES=0
HW_GPU_CORES=""
HW_OS_VERSION=""
HW_POWER_SOURCE=""
HW_DISK_AVAILABLE_GB=0

# ─── Usage ─────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'

  Mac LLM Bench — Benchmark LLMs on Apple Silicon

  USAGE:
    ./bench.sh [OPTIONS]

  MODEL SELECTION:
    --model <id>          Benchmark a specific model from the registry
    --model-path <path>   Benchmark a local GGUF file directly
    --custom <repo>       Benchmark a custom HuggingFace GGUF repo
    --quant <type>        Quantization type (default: Q4_K_M)
    --all                 Benchmark all models in the registry
    --auto                Benchmark all models that fit in your RAM
    --tag <tag>           Benchmark models with a specific tag
    --max-params <size>   Only models up to this size (e.g., 8B, 27B)

  BENCHMARK OPTIONS:
    --ngl <n>             GPU layers to offload (default: 99 = all)
    --threads <n>         CPU threads, 0 = auto (default: 0)
    --no-flash-attn       Disable flash attention
    --quality             Also run perplexity benchmark (WikiText-2)

  PARAMETER SWEEP:
    --sweep               Run parameter sweep (quick mode)
    --sweep-full          Run full parameter sweep

  DISK MANAGEMENT:
    --cleanup             Delete model after benchmarking
    --streaming           Download, benchmark, delete — one at a time
    --cache-dir <path>    Custom cache directory
    --cache-info          Show cache contents and size
    --cache-clear         Delete all cached models

  OTHER:
    --list                List available models
    --scan                Scan for locally cached GGUF models
    --results             Show benchmark results for this machine
    --quick               Quick smoke test (smallest model)
    --hardware            Show detected hardware info
    --help                Show this help

  EXAMPLES:
    ./bench.sh --quick                              # Quick test
    ./bench.sh --model gemma-3-4b                   # One model
    ./bench.sh --model gemma-3-4b --quant Q8_0      # Specific quant
    ./bench.sh --model gemma-3-4b --sweep           # Find optimal params
    ./bench.sh --model gemma-3-4b --quality         # Speed + quality
    ./bench.sh --auto                               # All that fit in RAM
    ./bench.sh --auto --streaming                   # Low disk space mode
    ./bench.sh --model-path ~/my-model.gguf         # Local file

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

# ─── List models ───────────────────────────────────────────────────
list_models() {
    local filter_tag="${1:-}"
    local filter_max_params="${2:-}"

    echo ""
    echo "  Available Models"
    echo "  ═══════════════════════════════════════════════════════════════"
    printf "  %-20s %-8s %-10s %-10s %s\n" "ID" "Params" "Min RAM" "Quant" "Tags"
    echo "  ─────────────────────────────────────────────────────────────"

    python3 -c "
import json, sys

data = json.loads('''$(parse_models)''')
models = data.get('models', {})

filter_tag = '$filter_tag'
filter_max_params = '$filter_max_params'

def parse_params(p):
    try: return float(str(p).replace('B', ''))
    except: return 999

max_p = parse_params(filter_max_params) if filter_max_params else 999

for mid, m in sorted(models.items()):
    tags = m.get('tags', [])
    if isinstance(tags, str): tags = [tags]
    params = m.get('params', '?')

    if filter_tag and filter_tag not in tags: continue
    if parse_params(params) > max_p: continue

    min_ram = m.get('min_ram', 0)
    default_q = m.get('default_quant', 'Q4_K_M')
    tag_str = ', '.join(tags) if tags else ''
    print(f'  {mid:<20} {params:<8} {min_ram:<10} {default_q:<10} {tag_str}')
" 2>/dev/null

    echo "  ═══════════════════════════════════════════════════════════════"
    echo ""
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

# ─── Check dependencies ───────────────────────────────────────────
check_dependencies() {
    local ok=true

    if ! command -v llama-bench &>/dev/null; then
        log_error "llama-bench not found"
        echo "  Install: brew install llama.cpp"
        echo "  Or build: https://github.com/ggml-org/llama.cpp"
        ok=false
    fi

    if ! command -v python3 &>/dev/null; then
        log_error "python3 not found"
        ok=false
    fi

    if ! command -v huggingface-cli &>/dev/null; then
        log_warn "huggingface-cli not found (needed for downloading models)"
        echo "  Install: pip install huggingface-hub"
    fi

    if [[ "$RUN_QUALITY" == "true" ]] && ! command -v llama-perplexity &>/dev/null; then
        log_warn "llama-perplexity not found — quality benchmark will be skipped"
        log_warn "Build llama.cpp from source to get llama-perplexity"
    fi

    [[ "$ok" == "true" ]]
}

# ─── Pre-flight ───────────────────────────────────────────────────
preflight() {
    load_hardware

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                    Mac LLM Bench                            ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    bash "$LIB_DIR/detect_hardware.sh" --summary
    echo ""

    if [[ "$HW_POWER_SOURCE" == "battery" ]]; then
        log_warn "Running on battery — results may be inconsistent."
        log_warn "Plug in for accurate benchmarks."
        echo ""
        read -rp "  [C]ontinue / [Q]uit: " choice
        [[ "$choice" =~ [Qq] ]] && exit 0
        echo ""
    fi

    check_dependencies || exit 1
}

# ─── Download model ───────────────────────────────────────────────
download_model_by_id() {
    local model_id="$1"
    local quant="$2"

    local model_info
    model_info=$(get_model_info "$model_id")
    if [[ -z "$model_info" || "$model_info" == "{}" ]]; then
        log_error "Model '$model_id' not found. Use --list to see available models."
        return 1
    fi

    local file_pattern
    file_pattern=$(echo "$model_info" | python3 -c "
import json, sys
m = json.load(sys.stdin)
print(m.get('file_pattern', '').replace('{quant}', '$quant'))
" 2>/dev/null)

    if [[ -z "$file_pattern" ]]; then
        log_error "Could not determine filename for $model_id ($quant)"
        return 1
    fi

    # Check cache
    mkdir -p "$CACHE_DIR"
    if [[ -f "$CACHE_DIR/$file_pattern" ]]; then
        log_ok "Cached: $file_pattern"
        echo "$CACHE_DIR/$file_pattern"
        return 0
    fi

    # Get sources
    local sources
    sources=$(echo "$model_info" | python3 -c "
import json, sys
m = json.load(sys.stdin)
for s in m.get('sources', []):
    gated = str(s.get('gated', False)).lower()
    print(s.get('repo', '') + ':' + gated)
" 2>/dev/null)

    # Try each source
    while IFS= read -r source_line; do
        [[ -z "$source_line" ]] && continue
        local repo="${source_line%%:*}"
        local gated="${source_line#*:}"

        if [[ "$gated" == "true" ]]; then
            if ! huggingface-cli whoami &>/dev/null 2>&1; then
                log_warn "$repo requires HuggingFace login"
                echo "  1. Accept license at https://huggingface.co/$repo"
                echo "  2. Run: huggingface-cli login"
                read -rp "  [S]kip / [R]etry / [Q]uit: " choice
                case "$choice" in
                    [Ss]) continue ;;
                    [Qq]) exit 0 ;;
                esac
            fi
        fi

        log_info "Downloading $file_pattern from $repo..."
        if huggingface-cli download "$repo" "$file_pattern" \
            --local-dir "$CACHE_DIR" \
            --local-dir-use-symlinks False 2>&1; then
            if [[ -f "$CACHE_DIR/$file_pattern" ]]; then
                log_ok "Downloaded: $file_pattern"
                echo "$CACHE_DIR/$file_pattern"
                return 0
            fi
        fi
        log_warn "Source failed, trying next..."
    done <<< "$sources"

    log_error "Failed to download $model_id"
    return 1
}

# ─── Benchmark a single model ─────────────────────────────────────
bench_single_model() {
    local model_id="$1"
    local model_path="$2"
    local quant="$3"
    local model_name="${4:-$model_id}"
    local model_params="${5:-unknown}"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Benchmarking: $model_name ($quant)"
    echo "  ngl=$N_GPU_LAYERS  flash_attn=$FLASH_ATTENTION  threads=$THREADS"
    echo "═══════════════════════════════════════════════════════════════"

    # Phase 1: Speed — llama-bench (THE core benchmark)
    echo ""
    log_info "Phase 1/3: Speed benchmark (llama-bench)"
    log_info "  Tests: pp128, pp256, pp512, tg128, tg256"

    local bench_args=()
    bench_args+=(-m "$model_path")
    bench_args+=(-ngl "$N_GPU_LAYERS")
    bench_args+=(-p "128,256,512")
    bench_args+=(-n "128,256")

    if [[ "$FLASH_ATTENTION" == "true" ]]; then
        bench_args+=(-fa 1)
    fi
    if [[ "$THREADS" -gt 0 ]]; then
        bench_args+=(-t "$THREADS")
    fi

    # Run with markdown output for display
    local raw_output
    raw_output=$(llama-bench "${bench_args[@]}" 2>&1) || true
    echo "$raw_output"

    # Run again with JSON for data capture
    local json_output
    json_output=$(llama-bench "${bench_args[@]}" -o json 2>&1) || true

    # Phase 2: Memory measurement
    echo ""
    log_info "Phase 2/3: Memory measurement"

    local peak_mem="0"
    local mem_output
    if mem_output=$(/usr/bin/time -l llama-bench \
        -m "$model_path" -ngl "$N_GPU_LAYERS" \
        -p "32" -n "1" 2>&1); then
        peak_mem=$(echo "$mem_output" | awk '/maximum resident set size/ {printf "%.2f", $1/1073741824}')
    fi
    log_ok "Peak memory: ${peak_mem} GB"

    # Phase 3: Quality (optional)
    local quality_json="{}"
    if [[ "$RUN_QUALITY" == "true" ]]; then
        echo ""
        log_info "Phase 3/3: Quality benchmark (perplexity on WikiText-2)"
        source "$LIB_DIR/run_bench.sh"
        quality_json=$(run_perplexity "$model_path" "$N_GPU_LAYERS" "$FLASH_ATTENTION" 2>/dev/null || echo "{}")
    else
        echo ""
        log_info "Phase 3/3: Quality — skipped (use --quality to enable)"
    fi

    # Save results
    local hw_json
    hw_json=$(bash "$LIB_DIR/detect_hardware.sh" --json)

    source "$LIB_DIR/collect_results.sh"
    local result_path
    result_path=$(save_result \
        "$hw_json" "$model_id" "$model_name" "$model_params" "$quant" "$model_path" \
        "$N_GPU_LAYERS" "$FLASH_ATTENTION" "$THREADS" \
        "$json_output" "$peak_mem" "$quality_json" "$raw_output" 2>/dev/null) || true

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    log_ok "Complete: $model_name ($quant)"
    if [[ -n "$result_path" ]]; then
        log_ok "Saved: $result_path"
    fi
    echo "═══════════════════════════════════════════════════════════════"
}

# ─── Get models to benchmark ──────────────────────────────────────
get_models_to_bench() {
    local filter="$1"

    python3 -c "
import json
data = json.loads('''$(parse_models)''')
models = data.get('models', {})

for mid, m in sorted(models.items()):
    min_ram = m.get('min_ram', 0)
    params = float(str(m.get('params', '999')).replace('B', ''))
    tags = m.get('tags', [])
    if isinstance(tags, str): tags = [tags]

    if '$filter' == 'auto' and min_ram > $HW_TOTAL_RAM_GB: continue
    if '$filter'.startswith('tag:'):
        if '$filter'.split(':',1)[1] not in tags: continue
    if '$filter'.startswith('max-params:'):
        if params > float('$filter'.split(':',1)[1].replace('B','')): continue

    print(mid)
" 2>/dev/null
}

# ─── Show plan ────────────────────────────────────────────────────
show_plan() {
    local model_ids=("$@")

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Benchmark Plan"
    echo "═══════════════════════════════════════════════════════════════"
    printf "\n  %-20s %-8s %-10s %s\n" "Model" "Quant" "Est. Size" "Status"
    echo "  ─────────────────────────────────────────────────────────────"

    for model_id in "${model_ids[@]}"; do
        local model_info quant params
        model_info=$(get_model_info "$model_id" 2>/dev/null || echo "{}")
        quant="${QUANT:-$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('default_quant','Q4_K_M'))" 2>/dev/null || echo "Q4_K_M")}"
        params=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('params','?'))" 2>/dev/null || echo "?")

        # Estimate size
        local num mult est
        num=$(echo "$params" | sed 's/[^0-9.]//g')
        case "$quant" in
            Q2_K) mult="0.30";; Q3_K_M) mult="0.40";; Q4_K_M) mult="0.55";;
            Q5_K_M) mult="0.65";; Q6_K) mult="0.75";; Q8_0) mult="1.00";; *) mult="0.55";;
        esac
        est=$(echo "$num * $mult" | bc 2>/dev/null || echo "?")

        # Check cache
        local file_pattern status_icon
        file_pattern=$(echo "$model_info" | python3 -c "
import json,sys; m=json.load(sys.stdin)
print(m.get('file_pattern','').replace('{quant}','$quant'))" 2>/dev/null)

        if [[ -f "$CACHE_DIR/$file_pattern" ]]; then
            status_icon="${GREEN}cached${NC}"
        else
            status_icon="${YELLOW}download${NC}"
        fi

        printf "  %-20s %-8s %-10s " "$model_id" "$quant" "${est}GB"
        echo -e "$status_icon"
    done

    echo ""
    echo "  Disk available: ${HW_DISK_AVAILABLE_GB}GB"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    read -rp "  Proceed? [Y/n]: " choice
    [[ "$choice" =~ [Nn] ]] && exit 0
}

# ─── Run benchmarks for model list ────────────────────────────────
run_benchmarks() {
    local model_ids=("$@")

    for model_id in "${model_ids[@]}"; do
        local model_info quant model_name model_params min_ram
        model_info=$(get_model_info "$model_id" 2>/dev/null || echo "{}")
        quant="${QUANT:-$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('default_quant','Q4_K_M'))" 2>/dev/null || echo "Q4_K_M")}"
        model_name=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name','$model_id'))" 2>/dev/null || echo "$model_id")
        model_params=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('params','?'))" 2>/dev/null || echo "?")
        min_ram=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('min_ram',0))" 2>/dev/null || echo "0")

        # RAM check
        if (( min_ram > HW_TOTAL_RAM_GB )); then
            log_warn "$model_id needs ${min_ram}GB RAM, you have ${HW_TOTAL_RAM_GB}GB"
            read -rp "  [S]kip / [F]orce / [Q]uit: " choice
            case "$choice" in
                [Ss]) continue ;; [Qq]) exit 0 ;;
            esac
        fi

        # Download
        local model_path
        if ! model_path=$(download_model_by_id "$model_id" "$quant"); then
            log_error "Could not download $model_id, skipping"
            continue
        fi

        # Sweep or bench
        if [[ -n "$SWEEP_MODE" ]]; then
            source "$LIB_DIR/run_sweep.sh"
            run_parameter_sweep "$model_path" "$SWEEP_MODE"
        else
            bench_single_model "$model_id" "$model_path" "$quant" "$model_name" "$model_params"
        fi

        # Cleanup
        if [[ "$CLEANUP" == "true" || "$STREAMING" == "true" ]]; then
            local filename
            filename=$(basename "$model_path")
            rm -f "$CACHE_DIR/$filename"
            log_ok "Cleaned up: $filename"
        fi
    done
}

# ─── Parse arguments ──────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)      MODEL="$2"; shift 2 ;;
            --model-path) MODEL_PATH="$2"; shift 2 ;;
            --custom)     CUSTOM_REPO="$2"; shift 2 ;;
            --quant)      QUANT="$2"; shift 2 ;;
            --all)        ACTION="bench_all"; shift ;;
            --auto)       ACTION="bench_auto"; shift ;;
            --tag)        TAG="$2"; ACTION="bench_tag"; shift 2 ;;
            --max-params) MAX_PARAMS="$2"; shift 2 ;;
            --ngl)        N_GPU_LAYERS="$2"; shift 2 ;;
            --threads)    THREADS="$2"; shift 2 ;;
            --no-flash-attn) FLASH_ATTENTION=false; shift ;;
            --quality)    RUN_QUALITY=true; shift ;;
            --sweep)      SWEEP_MODE="quick"; shift ;;
            --sweep-full) SWEEP_MODE="full"; shift ;;
            --cleanup)    CLEANUP=true; shift ;;
            --streaming)  STREAMING=true; shift ;;
            --cache-dir)  CACHE_DIR="$2"; export MAC_LLM_CACHE_DIR="$2"; shift 2 ;;
            --cache-info) ACTION="cache_info"; shift ;;
            --cache-clear) ACTION="cache_clear"; shift ;;
            --list)       ACTION="list"; shift ;;
            --scan)       ACTION="scan"; shift ;;
            --results)    ACTION="results"; shift ;;
            --quick)      ACTION="quick"; shift ;;
            --hardware)   ACTION="hardware"; shift ;;
            --help|-h)    usage; exit 0 ;;
            *)
                log_error "Unknown option: $1"
                echo "  Run ./bench.sh --help for usage"
                exit 1 ;;
        esac
    done
}

# ─── Main ──────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    case "$ACTION" in
        list)
            list_models "$TAG" "$MAX_PARAMS"
            ;;
        scan)
            source "$LIB_DIR/download_model.sh"
            scan_local_models
            ;;
        cache_info)
            source "$LIB_DIR/download_model.sh"
            cache_info
            ;;
        cache_clear)
            source "$LIB_DIR/download_model.sh"
            cache_clear
            ;;
        hardware)
            bash "$LIB_DIR/detect_hardware.sh" --summary
            ;;
        results)
            source "$LIB_DIR/collect_results.sh"
            print_results_summary
            ;;
        quick)
            preflight
            log_info "Quick test with gemma-3-1b (Q4_K_M)"
            run_benchmarks "gemma-3-1b"
            ;;
        bench_all)
            preflight
            local -a models
            mapfile -t models < <(get_models_to_bench "all")
            show_plan "${models[@]}"
            run_benchmarks "${models[@]}"
            ;;
        bench_auto)
            preflight
            local -a models
            mapfile -t models < <(get_models_to_bench "auto")
            [[ ${#models[@]} -eq 0 ]] && { log_error "No models fit in ${HW_TOTAL_RAM_GB}GB RAM"; exit 1; }
            show_plan "${models[@]}"
            run_benchmarks "${models[@]}"
            ;;
        bench_tag)
            preflight
            local -a models
            mapfile -t models < <(get_models_to_bench "tag:$TAG")
            [[ ${#models[@]} -eq 0 ]] && { log_error "No models with tag '$TAG'"; exit 1; }
            show_plan "${models[@]}"
            run_benchmarks "${models[@]}"
            ;;
        bench)
            if [[ -n "$MODEL_PATH" ]]; then
                preflight
                bench_single_model "custom" "$MODEL_PATH" "${QUANT:-unknown}" "Custom Model" "?"

            elif [[ -n "$CUSTOM_REPO" ]]; then
                preflight
                local custom_quant="${QUANT:-Q4_K_M}"
                local repo_name
                repo_name=$(basename "$CUSTOM_REPO")
                local guess="${repo_name}-${custom_quant}.gguf"
                log_info "Custom model: $CUSTOM_REPO ($guess)"

                mkdir -p "$CACHE_DIR"
                if huggingface-cli download "$CUSTOM_REPO" "$guess" \
                    --local-dir "$CACHE_DIR" --local-dir-use-symlinks False 2>&1; then
                    bench_single_model "custom-$repo_name" "$CACHE_DIR/$guess" "$custom_quant" "$repo_name" "?"
                else
                    log_error "Download failed. Check repo name and quant type."
                    exit 1
                fi

            elif [[ -n "$MODEL" ]]; then
                preflight
                run_benchmarks "$MODEL"

            else
                usage
                exit 0
            fi
            ;;
    esac
}

main "$@"
