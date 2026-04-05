#!/usr/bin/env bash
# run_bench.sh — Core benchmark using llama-bench (standardized, content-agnostic)
# Also supports optional perplexity measurement via llama-perplexity.

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

# ─── Check llama.cpp tools ────────────��───────────────────────────
check_llamacpp() {
    if ! command -v llama-bench &>/dev/null; then
        log_error "llama-bench not found."
        echo ""
        echo "  Install llama.cpp:"
        echo "    brew install llama.cpp"
        echo ""
        echo "  Or build from source:"
        echo "    git clone https://github.com/ggml-org/llama.cpp"
        echo "    cd llama.cpp && cmake -B build && cmake --build build --config Release"
        echo ""
        return 1
    fi
    return 0
}

get_llamacpp_version() {
    llama-bench --version 2>&1 | head -1 || echo "unknown"
}

# ─── Core: run llama-bench ─────────────────────────────────────────
# This is THE benchmark. Content-agnostic, standardized, reproducible.
# Tests prompt processing (pp) and text generation (tg) at fixed token counts.
run_llama_bench() {
    local model_path="$1"
    local n_gpu_layers="${2:-99}"
    local flash_attention="${3:-true}"
    local threads="${4:-0}"
    local output_format="${5:-json}"

    local args=()
    args+=(-m "$model_path")
    args+=(-ngl "$n_gpu_layers")

    # Standard test sizes: prompt processing and text generation
    args+=(-p "128,256,512")
    args+=(-n "128,256")

    if [[ "$flash_attention" == "true" ]]; then
        args+=(-fa 1)
    fi

    if [[ "$threads" -gt 0 ]]; then
        args+=(-t "$threads")
    fi

    # Output as JSON for parsing
    args+=(-o "$output_format")

    log_info "Running llama-bench..."
    log_info "  Model:      $(basename "$model_path")"
    log_info "  GPU Layers: $n_gpu_layers"
    log_info "  Flash Attn: $flash_attention"
    log_info "  Tests:      pp128, pp256, pp512, tg128, tg256"

    local output
    if output=$(llama-bench "${args[@]}" 2>&1); then
        echo "$output"
        return 0
    else
        log_error "llama-bench failed"
        echo "$output" >&2
        return 1
    fi
}

# ─── Parse llama-bench JSON output into our schema ──��──────────────
parse_llama_bench_json() {
    local raw_output="$1"

    python3 -c "
import json, sys, re

raw = '''$raw_output'''

# llama-bench with -o json outputs a JSON array of test results
# Each entry has: model, size, params, backend, ngl, test, t/s, etc.
speed = {}

# Try parsing as JSON first (llama-bench -o json)
try:
    results = json.loads(raw)
    if isinstance(results, list):
        for r in results:
            test = r.get('test', '')
            tps = r.get('t/s', 0)
            if test and tps:
                speed[test] = round(float(tps), 2)
except (json.JSONDecodeError, TypeError):
    # Fallback: parse markdown table output
    for line in raw.split('\n'):
        line = line.strip()
        if '|' not in line or line.startswith('|--') or 'model' in line.lower():
            continue
        parts = [p.strip() for p in line.split('|') if p.strip()]
        # llama-bench table: model | size | params | backend | ngl | test | t/s
        if len(parts) >= 7:
            test = parts[5].strip()
            try:
                tps = float(parts[6].strip().split()[0])
                speed[test] = round(tps, 2)
            except (ValueError, IndexError):
                pass

json.dump(speed, sys.stdout)
"
}

# ─── Measure peak memory ──────────────────────────────────────────
measure_memory() {
    local model_path="$1"
    local n_gpu_layers="${2:-99}"

    log_info "Measuring peak memory..."

    local output
    if output=$(/usr/bin/time -l llama-bench \
        -m "$model_path" \
        -ngl "$n_gpu_layers" \
        -p "32" \
        -n "1" \
        2>&1); then

        local peak_rss_bytes
        peak_rss_bytes=$(echo "$output" | awk '/maximum resident set size/ {print $1}')
        if [[ -n "$peak_rss_bytes" && "$peak_rss_bytes" -gt 0 ]]; then
            local peak_gb
            peak_gb=$(echo "scale=2; $peak_rss_bytes / 1073741824" | bc 2>/dev/null || echo "0")
            echo "$peak_gb"
            return 0
        fi
    fi

    echo "0"
}

# ─── Optional: perplexity on WikiText-2 ────────���──────────────────
# This measures quality — lower perplexity = better.
# Requires llama-perplexity and the WikiText-2 dataset.
WIKITEXT_URL="https://huggingface.co/datasets/ggml-org/ci/resolve/main/wikitext-2-raw-v1.zip"

ensure_wikitext() {
    local cache_dir="${MAC_LLM_CACHE_DIR:-$HOME/.cache/mac-llm-bench}"
    local wikitext_file="$cache_dir/wikitext-2-raw/wiki.test.raw"

    if [[ -f "$wikitext_file" ]]; then
        echo "$wikitext_file"
        return 0
    fi

    if ! command -v curl &>/dev/null; then
        log_error "curl required to download WikiText-2"
        return 1
    fi

    log_info "Downloading WikiText-2 dataset (~2MB)..."
    mkdir -p "$cache_dir"
    local zip_file="$cache_dir/wikitext-2-raw-v1.zip"

    if curl -sL "$WIKITEXT_URL" -o "$zip_file" && unzip -qo "$zip_file" -d "$cache_dir"; then
        rm -f "$zip_file"
        log_ok "WikiText-2 downloaded"
        echo "$wikitext_file"
        return 0
    else
        log_error "Failed to download WikiText-2"
        return 1
    fi
}

run_perplexity() {
    local model_path="$1"
    local n_gpu_layers="${2:-99}"
    local flash_attention="${3:-true}"

    if ! command -v llama-perplexity &>/dev/null; then
        log_warn "llama-perplexity not found — skipping quality benchmark"
        log_warn "Install llama.cpp from source for perplexity support"
        return 1
    fi

    local wikitext_file
    if ! wikitext_file=$(ensure_wikitext); then
        return 1
    fi

    local args=()
    args+=(-m "$model_path")
    args+=(-ngl "$n_gpu_layers")
    args+=(-f "$wikitext_file")
    args+=(--chunks 50)  # Limit to 50 chunks for reasonable runtime

    if [[ "$flash_attention" == "true" ]]; then
        args+=(-fa)
    fi

    log_info "Running perplexity benchmark on WikiText-2..."
    log_info "  This takes a while (measuring quality, not speed)"

    local output
    if output=$(llama-perplexity "${args[@]}" 2>&1); then
        # Parse perplexity from output
        # Format: "Final estimate: PPL = 5.1234 +/- 0.0567"
        local ppl ppl_std
        ppl=$(echo "$output" | grep -oP 'PPL\s*=\s*\K[0-9.]+' | tail -1 || echo "")
        ppl_std=$(echo "$output" | grep -oP '\+/-\s*\K[0-9.]+' | tail -1 || echo "")

        if [[ -n "$ppl" ]]; then
            log_ok "Perplexity: $ppl (+/- ${ppl_std:-?})"
            echo "{\"perplexity\": $ppl${ppl_std:+, \"perplexity_std\": $ppl_std}}"
            return 0
        fi
    fi

    log_error "Perplexity measurement failed"
    return 1
}

# ─── Full benchmark: speed + memory + optional quality ─────────────
run_full_benchmark() {
    local model_path="$1"
    local n_gpu_layers="${2:-99}"
    local flash_attention="${3:-true}"
    local threads="${4:-0}"
    local run_quality="${5:-false}"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Benchmark: $(basename "$model_path")"
    echo "═══════════════════════════���═══════════════════════════════════"

    # Phase 1: Speed (llama-bench)
    echo ""
    log_info "Phase 1/3: Speed benchmark (llama-bench)"
    local bench_output
    bench_output=$(run_llama_bench "$model_path" "$n_gpu_layers" "$flash_attention" "$threads" "json")
    local bench_exit=$?

    if [[ $bench_exit -eq 0 ]]; then
        # Also show human-readable output
        echo ""
        run_llama_bench "$model_path" "$n_gpu_layers" "$flash_attention" "$threads" "md" 2>/dev/null || true
    else
        log_error "Speed benchmark failed"
        return 1
    fi

    # Phase 2: Memory
    echo ""
    log_info "Phase 2/3: Memory measurement"
    local peak_mem
    peak_mem=$(measure_memory "$model_path" "$n_gpu_layers")
    log_ok "Peak memory: ${peak_mem} GB"

    # Phase 3: Quality (optional)
    local quality_json="{}"
    if [[ "$run_quality" == "true" ]]; then
        echo ""
        log_info "Phase 3/3: Quality benchmark (perplexity on WikiText-2)"
        quality_json=$(run_perplexity "$model_path" "$n_gpu_layers" "$flash_attention" 2>/dev/null || echo "{}")
    else
        echo ""
        log_info "Phase 3/3: Quality benchmark — skipped (use --quality to enable)"
    fi

    echo ""
    echo "═════════════��══════════════════════════════════���══════════════"
    log_ok "Benchmark complete"
    echo "══════════════════��════════════════════════════════════════════"

    # Return structured data for the caller
    echo "---BENCH_RESULTS---"
    echo "BENCH_OUTPUT=$bench_output"
    echo "PEAK_MEM=$peak_mem"
    echo "QUALITY=$quality_json"
}
