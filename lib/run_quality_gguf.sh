#!/usr/bin/env bash
# run_quality_gguf.sh — EvalPlus quality benchmark helpers for GGUF (llama-server)
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

# ─── Start llama-server in background ─────────────────────────────
# Usage: start_llama_server <model_path> <port> <context_size> <ngl> [no_think]
# Sets SERVER_PID in the calling shell (SERVER_PID must be declared there).
# When no_think="true", passes --reasoning-budget 0 to disable <think> output.
start_llama_server() {
    local model_path="$1"
    local port="${2:-8080}"
    local context_size="${3:-4096}"
    local ngl="${4:-99}"
    local no_think="${5:-false}"

    local cmd=(llama-server
        -m "$model_path"
        -c "$context_size"
        --port "$port"
        -ngl "$ngl"
        -np 1
    )

    if [[ "$no_think" == "true" ]]; then
        cmd+=(--reasoning-budget 0)
        log_info "  --no-think: adding --reasoning-budget 0"
    fi

    log_info "Starting llama-server..."
    log_info "  Command: ${cmd[*]}"

    "${cmd[@]}" &>/tmp/llama-server-$$.log &
    SERVER_PID=$!

    log_info "  PID: $SERVER_PID  |  log: /tmp/llama-server-$$.log"
}

# ─── Wait for llama-server to become ready ────────────────────────
# Usage: wait_for_server <port> [timeout_seconds]
# Returns 0 on success, 1 on timeout.
wait_for_server() {
    local port="${1:-8080}"
    local timeout="${2:-120}"
    local elapsed=0
    local spinner_chars=('|' '/' '-' '\\')
    local spin_idx=0

    log_info "Waiting for llama-server on port $port (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://localhost:${port}/health" 2>/dev/null || echo "000")

        if [[ "$http_code" == "200" ]]; then
            echo ""
            log_ok "Server is ready (${elapsed}s)"
            return 0
        fi

        # Show spinner
        printf "\r  [%s] %ds elapsed..." "${spinner_chars[$spin_idx]}" "$elapsed"
        spin_idx=$(( (spin_idx + 1) % 4 ))

        sleep 2
        elapsed=$(( elapsed + 2 ))
    done

    echo ""
    log_error "Server did not become ready within ${timeout}s"
    if [[ -f "/tmp/llama-server-$$.log" ]]; then
        log_error "Last server log lines:"
        tail -10 "/tmp/llama-server-$$.log" >&2
    fi
    return 1
}

# ─── Run EvalPlus code generation ────────────────────────────────
# Usage: run_evalplus_codegen <model_name> <dataset> <port> <output_dir>
# Writes generated samples to <output_dir>. Returns the path to the samples .jsonl file.
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

# ─── Run EvalPlus evaluation ─────────────────────────────────────
# Usage: run_evalplus_evaluate <dataset> <samples_jsonl_path>
# Returns exit code of evalplus.evaluate.
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

# ─── Stop llama-server ────────────────────────────────────────────
# Usage: stop_server
# Kills SERVER_PID if set and process exists.
stop_server() {
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_info "Stopping llama-server (PID: $SERVER_PID)..."
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
    rm -f "/tmp/llama-server-$$.log"
}
