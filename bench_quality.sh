#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════╗
# ║  Mac LLM Bench — Quality Benchmark (EvalPlus HumanEval / MBPP)  ║
# ║  Measures coding correctness via evalplus.codegen + evaluate     ║
# ║  Supports both GGUF (llama-server) and MLX (mlx_lm.server)      ║
# ╚═══════════════════════════════════════════════════════════════════╝

set -euo pipefail

export PATH="$PATH:/usr/sbin"

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
MLX_REPO=""
MODEL_PATH=""
RUNTIME="gguf"
PORT=8080
CONTEXT=4096
DATASET="humaneval"
N_GPU_LAYERS=99
CLEANUP=false
NO_THINK=false
CACHE_DIR="${MAC_LLM_CACHE_DIR:-$HOME/.cache/mac-llm-bench}"

# Hardware vars (populated by load_hardware)
HW_MAC_MODEL=""
HW_CHIP=""
HW_TOTAL_RAM_GB=0
HW_CPU_CORES=0
HW_GPU_CORES=""
HW_OS_VERSION=""
HW_POWER_SOURCE=""
HW_DISK_AVAILABLE_GB=0

# ─── Signal handling — prevent orphan server processes ─────────────
SERVER_PID=""

cleanup_server() {
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_warn "Caught signal — killing server (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    SERVER_PID=""
}

trap 'cleanup_server' EXIT INT TERM

# ─── Usage ─────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'

  Mac LLM Bench — Quality Benchmark (EvalPlus)

  USAGE:
    ./bench_quality.sh [OPTIONS]

  MODEL SELECTION:
    --model <id>          Model from registry (resolves GGUF path or MLX repo)
    --model-path <path>   Direct GGUF file path (bypasses registry)
    --repo <mlx-repo>     Direct MLX repo (bypasses registry, implies --runtime mlx)
    --quant <type>        Quantization for GGUF (default: from models.yaml)
    --all                 Batch: all models with coding-relevant tags
    --auto                Batch: coding models that fit in RAM
    --tag <tag>           Batch: models with a specific tag

  RUNTIME:
    --runtime gguf|mlx    Which runtime to use (default: gguf)
    --port <port>         Server port (default: 8080)
    --context <n>         Context window size (default: 4096; use 8192 for reasoning)

  EVAL OPTIONS:
    --dataset humaneval|mbpp   Eval dataset (default: humaneval)
    --no-think                 Disable reasoning/thinking mode (for Qwen3, Qwen3.5, Qwen3.6, DeepSeek-R1 models)

  DISK MANAGEMENT:
    --cleanup             Delete GGUF model after benchmark

  OTHER:
    --list                List available models
    --results             Show benchmark results
    --hardware            Show detected hardware info
    --help                Show this help

  EXAMPLES:
    ./bench_quality.sh --model qwen2.5-coder-7b
    ./bench_quality.sh --model qwen2.5-coder-7b --runtime mlx
    ./bench_quality.sh --model qwen2.5-coder-7b --dataset mbpp
    ./bench_quality.sh --repo mlx-community/Qwen2.5-Coder-7B-Instruct-4bit
    ./bench_quality.sh --model-path ~/models/my-coder.gguf --context 8192
    ./bench_quality.sh --auto --runtime gguf
    ./bench_quality.sh --tag coding --runtime mlx

EOF
}

# ─── HuggingFace CLI helper ─────────────────────────────────────────
_find_hf_cmd() {
    for cmd in hf huggingface-cli; do
        if command -v "$cmd" &>/dev/null; then
            echo "$cmd"; return 0
        fi
    done
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
        for cmd in hf huggingface-cli; do
            if [[ -x "$dir/$cmd" ]]; then
                echo "$dir/$cmd"; return 0
            fi
        done
    done
    return 1
}

hf_cmd() {
    local hf_bin
    if ! hf_bin=$(_find_hf_cmd); then
        log_error "Neither 'hf' nor 'huggingface-cli' found"
        echo "  Install: pip3 install huggingface-hub" >&2
        return 1
    fi
    "$hf_bin" "$@"
}

# ─── Parse YAML ────────────────────────────────────────────────────
parse_models() {
    python3 "$LIB_DIR/parse_yaml.py" "$SCRIPT_DIR/models.yaml" 2>/dev/null
}

# ─── Detect hardware ──────────────────────────────────────────────
load_hardware() {
    eval "$(bash "$LIB_DIR/detect_hardware.sh" --shell)"
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

# ─── Get MLX model info by ID ─────────────────────────────────────
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

# ─── List available models ─────────────────────────────────────────
list_models() {
    echo ""
    echo "  Available Models (Quality Benchmark)"
    echo "  ═══════════════════════════════════════════════════════════════"
    printf "  %-20s %-8s %-10s %-12s %s\n" "ID" "Params" "Min RAM" "MLX?" "Tags"
    echo "  ─────────────────────────────────────────────────────────────"

    python3 -c "
import json, sys
data = json.loads('''$(parse_models)''')
models = data.get('models', {})
for mid, m in sorted(models.items()):
    tags = m.get('tags', [])
    if isinstance(tags, str): tags = [tags]
    params = m.get('params', '?')
    min_ram = m.get('min_ram', 0)
    has_mlx = 'yes' if m.get('mlx_sources') else 'no'
    tag_str = ', '.join(tags) if tags else ''
    print(f'  {mid:<20} {params:<8} {min_ram:<10} {has_mlx:<12} {tag_str}')
" 2>/dev/null

    echo "  ═══════════════════════════════════════════════════════════════"
    echo ""
}

# ─── Check dependencies ───────────────────────────────────────────
check_dependencies() {
    local ok=true

    if ! command -v python3 &>/dev/null; then
        log_error "python3 not found"
        ok=false
    fi

    # Check evalplus
    if ! python3 -c "import evalplus" &>/dev/null 2>&1; then
        log_error "evalplus not found"
        echo "  Install: pip3 install evalplus"
        ok=false
    fi

    if [[ "$RUNTIME" == "gguf" ]]; then
        if ! command -v llama-server &>/dev/null; then
            log_error "llama-server not found"
            echo "  Install: brew install llama.cpp"
            echo "  Or build: https://github.com/ggml-org/llama.cpp"
            ok=false
        fi
        if ! _find_hf_cmd &>/dev/null; then
            log_warn "HuggingFace CLI not found (needed for downloading models)"
            echo "  Install: pip3 install huggingface-hub"
        fi
    else
        # MLX
        local mlx_server_ok=false
        if [[ -x "$HOME/.venvs/mlx/bin/mlx_lm.server" ]]; then
            mlx_server_ok=true
        elif command -v mlx_lm.server &>/dev/null; then
            mlx_server_ok=true
        fi
        if [[ "$mlx_server_ok" == "false" ]]; then
            log_error "mlx_lm.server not found"
            echo "  Install: pip3 install mlx-lm"
            ok=false
        fi
    fi

    [[ "$ok" == "true" ]]
}

# ─── Pre-flight ───────────────────────────────────────────────────
preflight() {
    load_hardware

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║              Mac LLM Bench — Quality Benchmark              ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    bash "$LIB_DIR/detect_hardware.sh" --summary
    echo ""

    # Check if project venv exists but is not activated
    if [[ -f "$SCRIPT_DIR/.venv/bin/activate" ]] && [[ -z "${VIRTUAL_ENV:-}" ]]; then
        log_warn "Project .venv found but not activated. Run: source .venv/bin/activate"
    fi

    if [[ "$HW_POWER_SOURCE" == "battery" ]]; then
        log_warn "Running on battery — results may be inconsistent."
        log_warn "Plug in for accurate benchmarks."
        if [[ -t 0 ]]; then
            echo ""
            read -rp "  [C]ontinue / [Q]uit: " choice
            [[ "$choice" =~ [Qq] ]] && exit 0
        fi
        echo ""
    fi

    check_dependencies || exit 1
}

# ─── Download model (GGUF) ────────────────────────────────────────
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
        log_ok "Cached: $file_pattern" >&2
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

    # Try each source (stdout = path, logs go to stderr)
    while IFS= read -r source_line; do
        [[ -z "$source_line" ]] && continue
        local repo="${source_line%%:*}"
        local gated="${source_line#*:}"

        if [[ "$gated" == "true" ]]; then
            if ! hf_cmd whoami &>/dev/null 2>&1; then
                log_warn "$repo requires HuggingFace login" >&2
                echo "  1. Accept license at https://huggingface.co/$repo" >&2
                echo "  2. Run: huggingface-cli login" >&2
                read -rp "  [S]kip / [R]etry / [Q]uit: " choice
                case "$choice" in
                    [Ss]) continue ;;
                    [Qq]) exit 0 ;;
                esac
            fi
        fi

        log_info "Downloading $file_pattern from $repo..." >&2
        local dl_output
        if dl_output=$(hf_cmd download "$repo" "$file_pattern" --local-dir "$CACHE_DIR" 2>&1); then
            if [[ -f "$CACHE_DIR/$file_pattern" ]]; then
                log_ok "Downloaded: $file_pattern" >&2
                echo "$CACHE_DIR/$file_pattern"
                return 0
            fi
            local resolved_path
            resolved_path=$(echo "$dl_output" | tail -1)
            if [[ -f "$resolved_path" ]]; then
                log_ok "Downloaded: $resolved_path" >&2
                echo "$resolved_path"
                return 0
            fi
        fi
        log_warn "Source failed, trying next..." >&2
    done <<< "$sources"

    log_error "Failed to download $model_id"
    return 1
}

# ─── Get models eligible for quality benchmarking ─────────────────
# Filters by runtime availability (sources vs mlx_sources) and optional tag/RAM.
get_quality_models() {
    local filter="$1"
    local runtime="$2"

    python3 -c "
import json
data = json.loads('''$(parse_models)''')
models = data.get('models', {})

for mid, m in sorted(models.items()):
    min_ram = m.get('min_ram', 0)
    tags = m.get('tags', [])
    if isinstance(tags, str): tags = [tags]

    # Runtime availability check
    if '$runtime' == 'mlx':
        if not m.get('mlx_sources'):
            continue
    else:
        if not m.get('sources'):
            continue

    if '$filter' == 'auto' and min_ram > $HW_TOTAL_RAM_GB: continue

    if '$filter'.startswith('tag:'):
        tag_filter = '$filter'.split(':', 1)[1]
        if tag_filter not in tags: continue

    if '$filter' == 'coding':
        # Default quality batch: coding tag only
        if 'coding' not in tags: continue

    print(mid)
" 2>/dev/null
}

# ─── Show quality benchmark plan ─────────────────────────────────
show_quality_plan() {
    local runtime="$1"
    shift
    local model_ids=("$@")

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Quality Benchmark Plan  (runtime: $runtime, dataset: $DATASET)"
    echo "═══════════════════════════════════════════════════════════════"
    printf "\n  %-20s %-8s %-10s %s\n" "Model" "Params" "Min RAM" "Source"
    echo "  ─────────────────────────────────────────────────────────────"

    for model_id in "${model_ids[@]}"; do
        local model_info params min_ram source_label
        model_info=$(get_model_info "$model_id" 2>/dev/null || echo "{}")
        params=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('params','?'))" 2>/dev/null || echo "?")
        min_ram=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('min_ram',0))" 2>/dev/null || echo "0")

        if [[ "$runtime" == "mlx" ]]; then
            source_label=$(echo "$model_info" | python3 -c "
import json, sys
m = json.load(sys.stdin)
mlx = m.get('mlx_sources', [])
print(mlx[0].get('repo','?') if mlx else '(no mlx_sources)')
" 2>/dev/null || echo "?")
        else
            local quant="${QUANT:-$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('default_quant','Q4_K_M'))" 2>/dev/null || echo "Q4_K_M")}"
            source_label="$quant"
        fi

        printf "  %-20s %-8s %-10s %s\n" "$model_id" "$params" "${min_ram}GB" "$source_label"
    done

    echo ""
    echo "  System RAM: ${HW_TOTAL_RAM_GB}GB  |  Disk available: ${HW_DISK_AVAILABLE_GB}GB"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    if [[ -t 0 ]]; then
        read -rp "  Proceed? [Y/n]: " choice
        [[ "$choice" =~ [Nn] ]] && exit 0
    fi
}

# ─── Run quality benchmark for a single GGUF model ────────────────
run_quality_gguf() {
    local model_id="$1"
    local model_path="$2"
    local quant="$3"
    local model_name="${4:-$model_id}"
    local model_params="${5:-?}"

    source "$LIB_DIR/run_quality_gguf.sh"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Quality Benchmark (GGUF): $model_name ($quant)"
    echo "  Dataset: $DATASET  |  Context: $CONTEXT  |  Port: $PORT"
    echo "═══════════════════════════════════════════════════════════════"

    # Phase 1: Start server
    echo ""
    log_info "Phase 1/4: Starting llama-server..."
    start_llama_server "$model_path" "$PORT" "$CONTEXT" "$N_GPU_LAYERS" "$NO_THINK"

    # Phase 2: Wait for server ready
    echo ""
    log_info "Phase 2/4: Waiting for server..."
    if ! wait_for_server "$PORT" 120; then
        log_error "Server startup failed"
        stop_server
        return 1
    fi

    # Phase 3: Code generation
    echo ""
    log_info "Phase 3/4: EvalPlus code generation..."
    local output_root="$SCRIPT_DIR/evalplus_results/${model_id}"
    local samples_file
    if ! samples_file=$(run_evalplus_codegen "$model_name" "$DATASET" "$PORT" "$output_root"); then
        log_error "Code generation failed"
        stop_server
        return 1
    fi

    # Phase 4: Evaluation
    echo ""
    log_info "Phase 4/4: EvalPlus evaluation..."
    # If codegen didn't return a valid file, try to find it
    if [[ ! -f "$samples_file" ]]; then
        samples_file=$(find "$output_root" -name "*.jsonl" ! -name "*.raw.jsonl" | head -1 2>/dev/null || true)
    fi
    if [[ -z "$samples_file" || ! -f "$samples_file" ]]; then
        log_error "No samples .jsonl file found in $output_root"
        stop_server
        return 1
    fi
    log_info "  Samples file: $samples_file"
    run_evalplus_evaluate "$DATASET" "$samples_file" || true

    # Stop server
    stop_server

    # Parse and merge results
    _parse_and_save_quality_results "$model_id" "$model_name" "$model_params" \
        "$quant" "$model_path" "$DATASET" "gguf" "$output_root"

    # Regenerate result tables
    log_info "Regenerating result tables..."
    python3 "$SCRIPT_DIR/scripts/generate_results.py" 2>/dev/null && log_ok "Tables regenerated" || log_warn "Table regeneration failed"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    log_ok "Quality benchmark complete: $model_name"
    echo "═══════════════════════════════════════════════════════════════"
}

# ─── Run quality benchmark for a single MLX model ─────────────────
run_quality_mlx() {
    local model_id="$1"
    local mlx_repo="$2"
    local model_name="${3:-$model_id}"
    local model_params="${4:-?}"

    source "$LIB_DIR/run_quality_mlx.sh"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Quality Benchmark (MLX): $model_name"
    echo "  Repo: $mlx_repo"
    echo "  Dataset: $DATASET  |  Port: $PORT"
    echo "═══════════════════════════════════════════════════════════════"

    # Phase 1: Start server
    echo ""
    log_info "Phase 1/4: Starting mlx_lm.server..."
    start_mlx_server "$mlx_repo" "$PORT" "$NO_THINK"

    # Phase 2: Wait for server ready (longer timeout — MLX downloads model)
    echo ""
    log_info "Phase 2/4: Waiting for server..."
    if ! wait_for_mlx_server "$PORT" 300; then
        log_error "Server startup failed"
        stop_server
        return 1
    fi

    # Phase 3: Code generation
    echo ""
    log_info "Phase 3/4: EvalPlus code generation..."
    local output_root="$SCRIPT_DIR/evalplus_results/${model_id}"
    local samples_file
    if ! samples_file=$(run_evalplus_codegen "$model_name" "$DATASET" "$PORT" "$output_root"); then
        log_error "Code generation failed"
        stop_server
        return 1
    fi

    # Phase 4: Evaluation
    echo ""
    log_info "Phase 4/4: EvalPlus evaluation..."
    if [[ ! -f "$samples_file" ]]; then
        samples_file=$(find "$output_root" -name "*.jsonl" ! -name "*.raw.jsonl" | head -1 2>/dev/null || true)
    fi
    if [[ -z "$samples_file" || ! -f "$samples_file" ]]; then
        log_error "No samples .jsonl file found in $output_root"
        stop_server
        return 1
    fi
    log_info "  Samples file: $samples_file"
    run_evalplus_evaluate "$DATASET" "$samples_file" || true

    # Stop server
    stop_server

    # Parse and merge results
    _parse_and_save_quality_results "$model_id" "$model_name" "$model_params" \
        "4bit" "$mlx_repo" "$DATASET" "mlx" "$output_root"

    # Regenerate result tables
    log_info "Regenerating result tables..."
    python3 "$SCRIPT_DIR/scripts/generate_results.py" 2>/dev/null && log_ok "Tables regenerated" || log_warn "Table regeneration failed"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    log_ok "Quality benchmark complete: $model_name (MLX)"
    echo "═══════════════════════════════════════════════════════════════"
}

# ─── Parse evalplus results and merge into result JSON ────────────
_parse_and_save_quality_results() {
    local model_id="$1"
    local model_name="$2"
    local model_params="$3"
    local quant="$4"
    local model_path="$5"
    local dataset="$6"
    local runtime="$7"
    local output_dir="$8"

    # These scripts are created by another agent — call them if they exist
    local parse_script="$LIB_DIR/parse_evalplus.py"
    local merge_script="$LIB_DIR/merge_quality_result.py"

    if [[ ! -f "$parse_script" ]]; then
        log_warn "lib/parse_evalplus.py not found — skipping result parsing"
        return 0
    fi

    log_info "Parsing EvalPlus results..."
    local quality_json
    quality_json=$(python3 "$parse_script" \
        --model "$model_name" \
        --dataset "$dataset" \
        --results-dir "$output_dir" 2>&1 || echo "{}")

    if [[ -z "$quality_json" || "$quality_json" == "{}" ]]; then
        log_warn "No quality scores parsed from EvalPlus output"
        return 0
    fi

    echo ""
    log_info "Quality scores: $quality_json"

    if [[ ! -f "$merge_script" ]]; then
        log_warn "lib/merge_quality_result.py not found — skipping result merge"
        return 0
    fi

    log_info "Merging quality results into benchmark JSON..."

    # Find the existing speed result JSON to merge into
    # Pattern: results/{gen}/{variant}/raw/{chip_folder}/{runtime}/{model_id}_{quant}_ngl*.json
    local result_file=""
    result_file=$(find "$SCRIPT_DIR/results" -path "*/${runtime}/${model_id}_${quant}_ngl*.json" 2>/dev/null | head -1)

    if [[ -z "$result_file" ]]; then
        # Try broader search
        result_file=$(find "$SCRIPT_DIR/results" -name "${model_id}_${quant}_*.json" -path "*/${runtime}/*" 2>/dev/null | head -1)
    fi

    if [[ -z "$result_file" ]]; then
        log_warn "No existing speed result found for ${model_id} ${quant} (${runtime}). Saving standalone quality result."
        # Create a path for standalone quality results
        local hw_info
        hw_info=$(bash "$LIB_DIR/detect_hardware.sh" --shell 2>/dev/null)
        eval "$hw_info" 2>/dev/null || true
        local gen="${HW_CHIP_GEN:-m5}"
        local variant="${HW_CHIP_VARIANT:-base}"
        local folder="${HW_FOLDER_NAME:-unknown}"
        result_file="$SCRIPT_DIR/results/${gen}/${variant}/raw/${folder}/${runtime}/${model_id}_${quant}_ngl99.json"
    fi

    log_info "  Result file: $result_file"
    python3 "$merge_script" \
        --result-file "$result_file" \
        --quality-json "$quality_json" || \
        log_warn "Could not merge quality results"
}

# ─── Run GGUF quality benchmark by model ID ──────────────────────
run_quality_for_model_gguf() {
    local model_id="$1"

    local model_info quant model_name model_params min_ram
    model_info=$(get_model_info "$model_id" 2>/dev/null || echo "{}")
    quant="${QUANT:-$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('default_quant','Q4_K_M'))" 2>/dev/null || echo "Q4_K_M")}"
    model_name=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name','$model_id'))" 2>/dev/null || echo "$model_id")
    model_params=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('params','?'))" 2>/dev/null || echo "?")
    min_ram=$(echo "$model_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('min_ram',0))" 2>/dev/null || echo "0")

    # RAM check
    if (( min_ram > HW_TOTAL_RAM_GB )); then
        log_warn "$model_id needs ${min_ram}GB RAM, you have ${HW_TOTAL_RAM_GB}GB"
        if [[ -t 0 ]]; then
            read -rp "  [S]kip / [F]orce / [Q]uit: " choice
            case "$choice" in
                [Ss]) return 0 ;; [Qq]) exit 0 ;;
            esac
        else
            log_warn "Skipping $model_id (non-interactive mode)"
            return 0
        fi
    fi

    local model_path
    if ! model_path=$(download_model_by_id "$model_id" "$quant"); then
        log_error "Could not download $model_id, skipping"
        return 1
    fi

    run_quality_gguf "$model_id" "$model_path" "$quant" "$model_name" "$model_params"

    if [[ "$CLEANUP" == "true" ]]; then
        local filename
        filename=$(basename "$model_path")
        rm -f "$CACHE_DIR/$filename"
        log_ok "Cleaned up: $filename"
    fi
}

# ─── Run MLX quality benchmark by model ID ───────────────────────
run_quality_for_model_mlx() {
    local model_id="$1"

    local info
    info=$(get_mlx_model_info "$model_id" 2>/dev/null || echo "")
    if [[ -z "$info" ]]; then
        log_error "No MLX mapping for '$model_id' — add mlx_sources to models.yaml or use --repo"
        return 1
    fi

    local repo model_name model_params min_ram
    IFS='|' read -r repo model_name model_params min_ram <<< "$info"

    # RAM check
    if (( min_ram > HW_TOTAL_RAM_GB )); then
        log_warn "$model_id needs ${min_ram}GB RAM, you have ${HW_TOTAL_RAM_GB}GB"
        if [[ -t 0 ]]; then
            read -rp "  [S]kip / [F]orce / [Q]uit: " choice
            case "$choice" in
                [Ss]) return 0 ;; [Qq]) exit 0 ;;
            esac
        else
            log_warn "Skipping $model_id (non-interactive mode)"
            return 0
        fi
    fi

    run_quality_mlx "$model_id" "$repo" "$model_name" "$model_params"
}

# ─── Parse arguments ──────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)      MODEL="$2"; shift 2 ;;
            --model-path) MODEL_PATH="$2"; shift 2 ;;
            --repo)       MLX_REPO="$2"; RUNTIME="mlx"; shift 2 ;;
            --quant)      QUANT="$2"; shift 2 ;;
            --runtime)    RUNTIME="$2"; shift 2 ;;
            --port)       PORT="$2"; shift 2 ;;
            --context)    CONTEXT="$2"; shift 2 ;;
            --dataset)    DATASET="$2"; shift 2 ;;
            --no-think)   NO_THINK=true; shift ;;
            --all)        ACTION="bench_all"; shift ;;
            --auto)       ACTION="bench_auto"; shift ;;
            --tag)        TAG="$2"; ACTION="bench_tag"; shift 2 ;;
            --cleanup)    CLEANUP=true; shift ;;
            --list)       ACTION="list"; shift ;;
            --results)    ACTION="results"; shift ;;
            --hardware)   ACTION="hardware"; shift ;;
            --help|-h)    usage; exit 0 ;;
            *)
                log_error "Unknown option: $1"
                echo "  Run ./bench_quality.sh --help for usage"
                exit 1 ;;
        esac
    done

    # Validate runtime
    if [[ "$RUNTIME" != "gguf" && "$RUNTIME" != "mlx" ]]; then
        log_error "Invalid --runtime: $RUNTIME (must be 'gguf' or 'mlx')"
        exit 1
    fi

    # Validate dataset
    if [[ "$DATASET" != "humaneval" && "$DATASET" != "mbpp" ]]; then
        log_error "Invalid --dataset: $DATASET (must be 'humaneval' or 'mbpp')"
        exit 1
    fi

    # Reasoning models need more context for <think> + code output
    if [[ "$NO_THINK" == "true" && "$CONTEXT" -eq 4096 ]]; then
        CONTEXT=8192
        log_warn "--no-think: bumping default context to 8192 for reasoning model"
    fi
}

# ─── Main ──────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    case "$ACTION" in
        list)
            list_models
            ;;
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
            while IFS= read -r line; do models+=("$line"); done \
                < <(get_quality_models "coding" "$RUNTIME")
            [[ ${#models[@]} -eq 0 ]] && {
                log_error "No models with 'coding' tag found for runtime '$RUNTIME'"
                exit 1
            }
            show_quality_plan "$RUNTIME" "${models[@]}"
            for m in "${models[@]}"; do
                if [[ "$RUNTIME" == "mlx" ]]; then
                    run_quality_for_model_mlx "$m" || log_error "Failed: $m"
                else
                    run_quality_for_model_gguf "$m" || log_error "Failed: $m"
                fi
            done
            ;;

        bench_auto)
            preflight
            local -a models=()
            while IFS= read -r line; do models+=("$line"); done \
                < <(get_quality_models "auto" "$RUNTIME")
            [[ ${#models[@]} -eq 0 ]] && {
                log_error "No models fit in ${HW_TOTAL_RAM_GB}GB RAM for runtime '$RUNTIME'"
                exit 1
            }
            show_quality_plan "$RUNTIME" "${models[@]}"
            for m in "${models[@]}"; do
                if [[ "$RUNTIME" == "mlx" ]]; then
                    run_quality_for_model_mlx "$m" || log_error "Failed: $m"
                else
                    run_quality_for_model_gguf "$m" || log_error "Failed: $m"
                fi
            done
            ;;

        bench_tag)
            preflight
            local -a models=()
            while IFS= read -r line; do models+=("$line"); done \
                < <(get_quality_models "tag:$TAG" "$RUNTIME")
            [[ ${#models[@]} -eq 0 ]] && {
                log_error "No models with tag '$TAG' for runtime '$RUNTIME'"
                exit 1
            }
            show_quality_plan "$RUNTIME" "${models[@]}"
            for m in "${models[@]}"; do
                if [[ "$RUNTIME" == "mlx" ]]; then
                    run_quality_for_model_mlx "$m" || log_error "Failed: $m"
                else
                    run_quality_for_model_gguf "$m" || log_error "Failed: $m"
                fi
            done
            ;;

        bench)
            if [[ -n "$MODEL_PATH" ]]; then
                # Direct GGUF file
                preflight
                RUNTIME="gguf"
                local quant="${QUANT:-unknown}"
                source "$LIB_DIR/run_quality_gguf.sh"
                run_quality_gguf "custom" "$MODEL_PATH" "$quant" "Custom Model" "?"

            elif [[ -n "$MLX_REPO" ]]; then
                # Direct MLX repo
                preflight
                local repo_name
                repo_name=$(echo "$MLX_REPO" | sed 's|.*/||')
                source "$LIB_DIR/run_quality_mlx.sh"
                run_quality_mlx "$(echo "$repo_name" | tr '[:upper:]' '[:lower:]')" \
                    "$MLX_REPO" "$repo_name" "?"

            elif [[ -n "$MODEL" ]]; then
                preflight
                if [[ "$RUNTIME" == "mlx" ]]; then
                    run_quality_for_model_mlx "$MODEL"
                else
                    run_quality_for_model_gguf "$MODEL"
                fi

            else
                usage
                exit 0
            fi
            ;;
    esac
}

main "$@"
