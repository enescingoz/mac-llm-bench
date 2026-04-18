#!/usr/bin/env bash
# run_quality_mlx.sh — EvalPlus quality benchmark helpers for MLX (mlx_lm.server)
# Sourced by bench_quality.sh. Provides server lifecycle and evalplus runner functions.

# Colors (safe to re-declare — idempotent)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Find mlx_lm.server binary ────────────────────────────────────
_find_mlx_server() {
    # Check MLX venv first (recommended install method)
    if [[ -x "$HOME/.venvs/mlx/bin/mlx_lm.server" ]]; then
        echo "$HOME/.venvs/mlx/bin/mlx_lm.server"
        return 0
    fi
    if command -v mlx_lm.server &>/dev/null; then
        echo "mlx_lm.server"
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
        if [[ -x "$dir/mlx_lm.server" ]]; then
            echo "$dir/mlx_lm.server"
            return 0
        fi
    done
    return 1
}

# ─── Start mlx_lm.server in background ───────────────────────────
# Usage: start_mlx_server <mlx_repo> <port>
# Sets SERVER_PID in the calling shell (SERVER_PID must be declared there).
start_mlx_server() {
    local mlx_repo="$1"
    local port="${2:-8080}"

    local mlx_server_bin
    if ! mlx_server_bin=$(_find_mlx_server); then
        log_error "mlx_lm.server not found"
        echo "  Install: pip3 install mlx-lm"
        return 1
    fi

    local cmd=("$mlx_server_bin" --model "$mlx_repo" --port "$port")

    log_info "Starting mlx_lm.server..."
    log_info "  Command: ${cmd[*]}"

    "${cmd[@]}" &>/tmp/mlx-server-$$.log &
    SERVER_PID=$!

    log_info "  PID: $SERVER_PID  |  log: /tmp/mlx-server-$$.log"
}

# ─── Wait for mlx_lm.server to become ready ──────────────────────
# Usage: wait_for_mlx_server <port> [timeout_seconds]
# Polls /v1/models (mlx_lm.server may not expose /health).
# Returns 0 on success, 1 on timeout.
wait_for_mlx_server() {
    local port="${1:-8080}"
    local timeout="${2:-180}"
    local elapsed=0
    local spinner_chars=('|' '/' '-' '\\')
    local spin_idx=0

    log_info "Waiting for mlx_lm.server on port $port (timeout: ${timeout}s)..."
    log_info "  Note: MLX model download may occur on first use — this can take a while"

    while [[ $elapsed -lt $timeout ]]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://localhost:${port}/v1/models" 2>/dev/null || echo "000")

        if [[ "$http_code" == "200" ]]; then
            echo ""
            log_ok "Server is ready (${elapsed}s)"
            return 0
        fi

        # Also check if the process has already died
        if [[ -n "${SERVER_PID:-}" ]] && ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo ""
            log_error "mlx_lm.server process exited unexpectedly"
            if [[ -f "/tmp/mlx-server-$$.log" ]]; then
                log_error "Last server log lines:"
                tail -10 "/tmp/mlx-server-$$.log" >&2
            fi
            return 1
        fi

        # Show spinner
        printf "\r  [%s] %ds elapsed..." "${spinner_chars[$spin_idx]}" "$elapsed"
        spin_idx=$(( (spin_idx + 1) % 4 ))

        sleep 2
        elapsed=$(( elapsed + 2 ))
    done

    echo ""
    log_error "Server did not become ready within ${timeout}s"
    if [[ -f "/tmp/mlx-server-$$.log" ]]; then
        log_error "Last server log lines:"
        tail -10 "/tmp/mlx-server-$$.log" >&2
    fi
    return 1
}

# ─── Run EvalPlus code generation (identical to GGUF version) ────
# Usage: run_evalplus_codegen <model_name> <dataset> <port> <output_dir>
# EvalPlus talks to the OpenAI-compatible API — it doesn't care which server is behind it.
run_evalplus_codegen() {
    local model_name="$1"
    local dataset="${2:-humaneval}"
    local port="${3:-8080}"
    local output_dir="${4:-evalplus_results}"

    mkdir -p "$output_dir"

    log_info "Running EvalPlus code generation..."
    log_info "  Model:   $model_name"
    log_info "  Dataset: $dataset"
    log_info "  Server:  http://localhost:${port}/v1"
    log_info "  Output:  $output_dir"

    # evalplus.codegen positional args: MODEL DATASET
    # --root sets the base output directory
    # Output lands at: {root}/{dataset}/{model_name}_openai_temp_0.0.jsonl
    local cmd=(python3 -m evalplus.codegen
        "$model_name"
        "$dataset"
        --backend openai
        --base-url "http://localhost:${port}/v1"
        --greedy
        --root "$output_dir"
    )

    log_info "  Command: ${cmd[*]}"

    if "${cmd[@]}"; then
        # Find the generated samples .jsonl file
        local samples_file
        samples_file=$(find "$output_dir" -name "*.jsonl" ! -name "*.raw.jsonl" -newer "$output_dir" 2>/dev/null | head -1)
        if [[ -z "$samples_file" ]]; then
            # Fallback: try the expected path pattern
            samples_file="${output_dir}/${dataset}/${model_name}_openai_temp_0.0.jsonl"
        fi
        log_ok "Code generation complete: $samples_file"
        echo "$samples_file"
        return 0
    else
        log_error "evalplus.codegen failed"
        return 1
    fi
}

# ─── Run EvalPlus evaluation (identical to GGUF version) ─────────
# Usage: run_evalplus_evaluate <dataset> <samples_jsonl_path>
run_evalplus_evaluate() {
    local dataset="${1:-humaneval}"
    local samples_path="${2:-}"

    # macOS setrlimit workaround
    export EVALPLUS_MAX_MEMORY_BYTES=-1

    log_info "Running EvalPlus evaluation..."
    log_info "  Dataset: $dataset"
    log_info "  Samples: $samples_path"

    # evalplus.evaluate: --samples points to the .jsonl file from codegen
    # Pipe 'y' to handle interactive overwrite prompt (EOFError in background)
    local cmd="python3 -m evalplus.evaluate --dataset $dataset --samples \"$samples_path\" --i-just-wanna-run"

    log_info "  Command: $cmd"

    if yes | eval "$cmd"; then
        log_ok "Evaluation complete"
        return 0
    else
        log_error "evalplus.evaluate failed"
        return 1
    fi
}

# ─── Stop mlx_lm.server ───────────────────────────────────────────
# Usage: stop_server
# Kills SERVER_PID if set and process exists.
stop_server() {
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_info "Stopping mlx_lm.server (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        # Wait up to 5s for clean shutdown
        local i
        for i in 1 2 3 4 5; do
            if ! kill -0 "$SERVER_PID" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        # Force kill if still running
        if kill -0 "$SERVER_PID" 2>/dev/null; then
            kill -9 "$SERVER_PID" 2>/dev/null || true
        fi
        log_ok "Server stopped"
    fi
    SERVER_PID=""
    # Clean up temp log
    rm -f "/tmp/mlx-server-$$.log"
}
