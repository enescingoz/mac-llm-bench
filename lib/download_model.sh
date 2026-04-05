#!/usr/bin/env bash
# download_model.sh — Download GGUF models from HuggingFace
# Handles gated models, caching, disk space checks, and local model scanning.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CACHE_DIR="$HOME/.cache/mac-llm-bench"

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

# Get cache directory
get_cache_dir() {
    echo "${MAC_LLM_CACHE_DIR:-$DEFAULT_CACHE_DIR}"
}

# Ensure cache directory exists
ensure_cache_dir() {
    local cache_dir
    cache_dir=$(get_cache_dir)
    mkdir -p "$cache_dir"
    echo "$cache_dir"
}

# Check if a model file already exists in cache
check_cache() {
    local filename="$1"
    local cache_dir
    cache_dir=$(get_cache_dir)
    local filepath="$cache_dir/$filename"

    if [[ -f "$filepath" ]]; then
        echo "$filepath"
        return 0
    fi
    return 1
}

# Scan for existing models in common locations
scan_local_models() {
    local search_paths=(
        "$(get_cache_dir)"
    )

    # LM Studio default path
    local lmstudio_dir="$HOME/.cache/lm-studio/models"
    if [[ -d "$lmstudio_dir" ]]; then
        search_paths+=("$lmstudio_dir")
    fi

    # Ollama models (stored as blobs, but we can check manifests)
    local ollama_dir="$HOME/.ollama/models"
    if [[ -d "$ollama_dir" ]]; then
        log_info "Ollama models directory found at $ollama_dir"
        log_info "Note: Ollama uses a different format. Use --runtime ollama to benchmark Ollama models directly."
    fi

    # Search for GGUFs
    local found=0
    for dir in "${search_paths[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' gguf; do
                local size_gb
                size_gb=$(du -g "$gguf" 2>/dev/null | awk '{print $1}')
                local basename
                basename=$(basename "$gguf")
                echo "  $basename (${size_gb}GB) — $gguf"
                found=$((found + 1))
            done < <(find "$dir" -name "*.gguf" -print0 2>/dev/null)
        fi
    done

    if [[ $found -eq 0 ]]; then
        log_info "No cached GGUF models found."
    else
        log_info "Found $found cached model(s)."
    fi
}

# Check available disk space
check_disk_space() {
    local required_gb="$1"
    local available_gb
    available_gb=$(df -g "$(get_cache_dir)" 2>/dev/null | awk 'NR==2 {print $4}')

    if (( available_gb < required_gb + 2 )); then
        log_warn "Low disk space: ${available_gb}GB available, ${required_gb}GB needed"
        log_warn "Consider using --cleanup to delete models after benchmarking"
        return 1
    fi
    return 0
}

# Estimate model file size based on params and quant
estimate_size_gb() {
    local params="$1"
    local quant="$2"

    # Extract numeric part of params (e.g., "7B" -> 7)
    local num
    num=$(echo "$params" | sed 's/[^0-9.]//g')

    # Rough size multipliers per quant type (GB per billion params)
    local multiplier
    case "$quant" in
        Q2_K)   multiplier="0.30" ;;
        Q3_K_M) multiplier="0.40" ;;
        Q4_K_M) multiplier="0.55" ;;
        Q5_K_M) multiplier="0.65" ;;
        Q6_K)   multiplier="0.75" ;;
        Q8_0)   multiplier="1.00" ;;
        F16)    multiplier="2.00" ;;
        *)      multiplier="0.55" ;;
    esac

    echo "$num * $multiplier" | bc 2>/dev/null || echo "0"
}

# Download a model from HuggingFace
download_model() {
    local repo="$1"
    local filename="$2"
    local gated="${3:-false}"
    local cache_dir
    cache_dir=$(ensure_cache_dir)
    local filepath="$cache_dir/$filename"

    # Check if already cached
    if [[ -f "$filepath" ]]; then
        log_ok "Model already cached: $filepath"
        echo "$filepath"
        return 0
    fi

    # Check if huggingface-cli is available
    if ! command -v huggingface-cli &>/dev/null; then
        log_error "huggingface-cli not found."
        echo ""
        echo "  Install it with:  pip install huggingface-hub"
        echo "  Or with:          brew install huggingface-cli"
        echo ""
        return 1
    fi

    # Handle gated models
    if [[ "$gated" == "true" ]]; then
        # Check if user is logged in
        if ! huggingface-cli whoami &>/dev/null; then
            log_warn "Model '$repo' requires HuggingFace authentication."
            echo ""
            echo "  This is a gated model. To access it:"
            echo "  1. Create an account at https://huggingface.co"
            echo "  2. Accept the model license at https://huggingface.co/$repo"
            echo "  3. Run: huggingface-cli login"
            echo ""
            read -rp "  [S]kip this model / [R]etry after login / [Q]uit: " choice
            case "$choice" in
                [Ss]) return 2 ;;  # Skip
                [Rr]) download_model "$repo" "$filename" "$gated"; return $? ;;
                *)    exit 1 ;;
            esac
        fi
    fi

    log_info "Downloading $filename from $repo..."
    log_info "Destination: $filepath"

    # Download using huggingface-cli
    if huggingface-cli download "$repo" "$filename" \
        --local-dir "$cache_dir" \
        --local-dir-use-symlinks False 2>&1; then
        log_ok "Download complete: $filepath"
        echo "$filepath"
        return 0
    else
        log_error "Download failed for $filename from $repo"
        # Clean up partial download
        rm -f "$filepath"
        return 1
    fi
}

# Try downloading from multiple sources (ungated first)
download_with_fallback() {
    local model_id="$1"
    local filename="$2"
    shift 2
    # Remaining args are "repo:gated" pairs
    local sources=("$@")

    # Check cache first
    local cached
    if cached=$(check_cache "$filename"); then
        log_ok "Using cached model: $cached"
        echo "$cached"
        return 0
    fi

    # Try each source
    for source in "${sources[@]}"; do
        local repo="${source%%:*}"
        local gated="${source#*:}"

        log_info "Trying source: $repo (gated=$gated)"
        local result
        if result=$(download_model "$repo" "$filename" "$gated"); then
            echo "$result"
            return 0
        fi
        local exit_code=$?

        if [[ $exit_code -eq 2 ]]; then
            # User chose to skip
            return 2
        fi

        log_warn "Source failed, trying next..."
    done

    log_error "All sources failed for $model_id"
    return 1
}

# Delete a cached model
cleanup_model() {
    local filename="$1"
    local cache_dir
    cache_dir=$(get_cache_dir)
    local filepath="$cache_dir/$filename"

    if [[ -f "$filepath" ]]; then
        local size
        size=$(du -h "$filepath" | awk '{print $1}')
        rm -f "$filepath"
        log_ok "Deleted $filename ($size freed)"
    fi
}

# Show cache info
cache_info() {
    local cache_dir
    cache_dir=$(get_cache_dir)

    echo "═══════════════════════════════════════════════════"
    echo "  Model Cache"
    echo "═══════════════════════════════════════════════════"
    echo "  Location: $cache_dir"

    if [[ ! -d "$cache_dir" ]]; then
        echo "  Status:   Empty (directory does not exist)"
        return
    fi

    local total_size
    total_size=$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}')
    local file_count
    file_count=$(find "$cache_dir" -name "*.gguf" 2>/dev/null | wc -l | tr -d ' ')

    echo "  Models:   $file_count GGUF file(s)"
    echo "  Size:     $total_size"
    echo ""

    if [[ $file_count -gt 0 ]]; then
        echo "  Files:"
        find "$cache_dir" -name "*.gguf" -exec du -h {} \; 2>/dev/null | sort -rh | while read -r size path; do
            echo "    $size  $(basename "$path")"
        done
    fi

    echo "═══════════════════════════════════════════════════"
}

# Clear entire cache
cache_clear() {
    local cache_dir
    cache_dir=$(get_cache_dir)

    if [[ ! -d "$cache_dir" ]]; then
        log_info "Cache is already empty."
        return
    fi

    local total_size
    total_size=$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}')

    read -rp "Delete all cached models ($total_size)? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$cache_dir"
        log_ok "Cache cleared ($total_size freed)"
    fi
}

# Main entry point for standalone usage
case "${1:-}" in
    --scan)       scan_local_models ;;
    --cache-info) cache_info ;;
    --cache-clear) cache_clear ;;
    --help)
        echo "Usage: download_model.sh [--scan|--cache-info|--cache-clear]"
        echo ""
        echo "  --scan         Scan for locally cached GGUF models"
        echo "  --cache-info   Show cache location and contents"
        echo "  --cache-clear  Delete all cached models"
        ;;
esac
