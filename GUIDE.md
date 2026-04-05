# User Guide

Everything you need to benchmark LLMs on your Mac.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Testing Predefined Models](#testing-predefined-models)
- [Testing Custom Models](#testing-custom-models)
- [Understanding Results](#understanding-results)
- [Parameter Tuning](#parameter-tuning)
- [Parameter Sweep](#parameter-sweep)
- [Quality Benchmark](#quality-benchmark)
- [Managing Disk Space](#managing-disk-space)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required

1. **Apple Silicon Mac** (M1/M2/M3/M4/M5)

2. **llama.cpp**
   ```bash
   brew install llama.cpp
   ```

3. **huggingface-cli**
   ```bash
   pip install huggingface-hub
   ```

### Optional

- **PyYAML** — better model registry parsing (fallback works without it)
  ```bash
  pip install pyyaml
  ```

- **llama-perplexity** — for quality benchmarks (build llama.cpp from source)
  ```bash
  git clone https://github.com/ggml-org/llama.cpp
  cd llama.cpp && cmake -B build && cmake --build build --config Release
  ```

### HuggingFace Login

All models in the initial set (Gemma 3) are **ungated** — no login required. If you add gated models later (Llama, etc.), the script will guide you through authentication.

---

## Quick Start

```bash
git clone https://github.com/user/mac-llm-bench.git
cd mac-llm-bench

# Verify hardware detection
./bench.sh --hardware

# Quick smoke test (Gemma 3 1B, ~0.5GB download)
./bench.sh --quick

# View results
./bench.sh --results
```

---

## Testing Predefined Models

### List Available Models

```bash
./bench.sh --list                   # All models
./bench.sh --list --tag gemma       # Filter by tag
./bench.sh --list --max-params 12B  # Filter by size
```

### Benchmark One Model

```bash
./bench.sh --model gemma-3-4b                # Default quant (Q4_K_M)
./bench.sh --model gemma-3-4b --quant Q8_0   # Specific quant
```

### Benchmark All Models

```bash
./bench.sh --auto    # All that fit in your RAM
./bench.sh --all     # Everything (needs enough RAM + disk)
```

---

## Testing Custom Models

### Local GGUF File

If you have a GGUF file from LM Studio or downloaded manually:

```bash
./bench.sh --model-path /path/to/model.gguf
```

### From HuggingFace

```bash
./bench.sh --custom username/model-GGUF --quant Q4_K_M
```

### Scan for Existing Models

```bash
./bench.sh --scan   # Finds GGUFs in cache, LM Studio, etc.
```

---

## Understanding Results

### What llama-bench Measures

`llama-bench` is content-agnostic — it doesn't use real prompts. It measures:

- **pp128, pp256, pp512** — Prompt Processing at 128/256/512 tokens. How fast the model reads your input. Higher = better.
- **tg128, tg256** — Text Generation at 128/256 tokens. How fast the model writes output. Higher = better.

These are the **only speed metrics that matter** for comparing hardware. They're fixed, standardized, and reproducible regardless of what you actually ask the model.

### Speed Ranges (for tg128)

| Range | Feel |
|-------|------|
| 50+ tok/s | Instant — faster than reading speed |
| 30-50 tok/s | Fast — great for interactive use |
| 15-30 tok/s | Good — comfortable for chat |
| 5-15 tok/s | Usable — noticeable delay |
| <5 tok/s | Slow — batch processing only |

### Memory

Peak RSS (Resident Set Size) — how much RAM the model uses. If this exceeds your total RAM, macOS will swap to disk and performance will crater.

---

## Parameter Tuning

### GPU Layers (`--ngl`)

How many model layers run on Metal GPU vs CPU.

```bash
./bench.sh --model gemma-3-4b --ngl 99   # All GPU (default, fastest)
./bench.sh --model gemma-3-4b --ngl 0    # CPU only (slowest)
```

**Rule:** Use `99` unless the model doesn't fit in memory. Then reduce until it loads.

### Flash Attention

Optimized attention computation. Faster and uses less memory.

```bash
./bench.sh --model gemma-3-4b                   # Enabled (default)
./bench.sh --model gemma-3-4b --no-flash-attn   # Disabled (for comparison)
```

### Threads (`--threads`)

CPU threads. `0` = auto-detect (usually best).

```bash
./bench.sh --model gemma-3-4b --threads 4   # Manual
```

### Quantization (`--quant`)

The biggest lever. Trades quality for speed and memory:

| Quant | Quality | Speed | RAM | When to Use |
|-------|---------|-------|-----|-------------|
| Q2_K | Poor | Fastest | Smallest | Only to check if model loads |
| Q3_K_M | Mediocre | Fast | Small | Very tight RAM |
| **Q4_K_M** | **Good** | **Fast** | **Medium** | **Default — best balance** |
| Q5_K_M | Very Good | Medium | Medium | Want better quality |
| Q6_K | Excellent | Slower | Large | Near-lossless |
| Q8_0 | Near-Perfect | Slow | 2x of Q4 | Maximum quality |

---

## Parameter Sweep

Automatically tests many parameter combinations to find the best settings.

### Quick Sweep (~8 combinations)

```bash
./bench.sh --model gemma-3-4b --sweep
```

### Full Sweep (~96 combinations)

```bash
./bench.sh --model gemma-3-4b --sweep-full
```

### Output

The sweep reports:
- **Top 5 fastest configs**
- **Max Speed** — absolute fastest
- **Long Context** — fastest with 8K+ context
- **CPU Only** — fallback config

---

## Quality Benchmark

Speed is easy to measure. Quality (how good the model's output is) is harder. We use **perplexity on WikiText-2** — a standard metric where lower = better.

```bash
./bench.sh --model gemma-3-4b --quality
```

This:
1. Downloads WikiText-2 (~2MB, cached)
2. Runs `llama-perplexity` on 50 chunks
3. Reports perplexity score

**Requires** `llama-perplexity` (build llama.cpp from source).

### Why Perplexity?

It tells you how much quality you lose from quantization:

```
gemma-3-4b F16:    PPL = 6.2   (baseline)
gemma-3-4b Q8_0:   PPL = 6.3   (barely any loss)
gemma-3-4b Q4_K_M: PPL = 6.8   (small loss, much faster)
gemma-3-4b Q2_K:   PPL = 9.1   (significant loss)
```

---

## Managing Disk Space

### Check Cache

```bash
./bench.sh --cache-info
```

### Benchmark with Cleanup

```bash
./bench.sh --model gemma-3-12b --cleanup         # Delete after bench
./bench.sh --auto --streaming                     # Download-bench-delete loop
```

### Custom Cache Location

```bash
./bench.sh --auto --cache-dir /Volumes/External/cache
# Or:
export MAC_LLM_CACHE_DIR=/Volumes/External/cache
```

### Clear Cache

```bash
./bench.sh --cache-clear
```

---

## Troubleshooting

### "llama-bench not found"
```bash
brew install llama.cpp
```

### "huggingface-cli not found"
```bash
pip install huggingface-hub
```

### Model download fails
- Check internet connection
- For gated models: `huggingface-cli login`
- Try a different source: check `models.yaml` for alternatives

### System freezes / swap
The model is too large. Options:
1. Smaller quant: `--quant Q3_K_M`
2. Fewer GPU layers: `--ngl 16`
3. Smaller model: `./bench.sh --list --max-params 4B`

### Inconsistent results
- **Plug in** your MacBook
- Close other apps (browsers, Docker, IDEs)
- Wait for thermal cooldown between runs
- Run multiple times — some variance is normal
