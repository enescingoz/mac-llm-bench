# User Guide

Everything you need to benchmark LLMs on your Mac.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [GGUF Benchmarks](#gguf-benchmarks)
- [MLX Benchmarks](#mlx-benchmarks)
- [Testing Custom Models](#testing-custom-models)
- [Understanding Results](#understanding-results)
- [Parameter Tuning](#parameter-tuning)
- [Parameter Sweep](#parameter-sweep)
- [Quality Benchmarks](#quality-benchmarks)
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

### MLX Benchmarks (optional)

4. **Python 3.10+** (macOS ships 3.9, so install via Homebrew)
   ```bash
   brew install python@3.12
   ```

5. **mlx-lm** (in a virtual environment)
   ```bash
   python3.12 -m venv ~/.venvs/mlx
   source ~/.venvs/mlx/bin/activate
   pip install mlx-lm
   ```

> **Note:** Some newer models (e.g., Gemma 4) may not yet be supported by mlx-lm. Support is added as the library updates.

### Optional

- **PyYAML** — better model registry parsing (fallback works without it)
  ```bash
  pip install pyyaml
  ```

- **llama-perplexity** — for perplexity quality benchmarks (build llama.cpp from source)
  ```bash
  git clone https://github.com/ggml-org/llama.cpp
  cd llama.cpp && cmake -B build && cmake --build build --config Release
  ```

- **evalplus** — for HumanEval+ code quality benchmarks
  ```bash
  pip install evalplus
  ```

### HuggingFace Login

All models in the initial set (Gemma 3) are **ungated** — no login required. If you add gated models later (Llama, etc.), the script will guide you through authentication.

---

## Quick Start

```bash
git clone https://github.com/enescingoz/mac-llm-bench.git
cd mac-llm-bench

# Verify hardware detection
./bench_gguf.sh --hardware

# Quick smoke test (Gemma 3 1B, ~0.5GB download)
./bench_gguf.sh --quick

# View results
./bench_gguf.sh --results
```

---

## GGUF Benchmarks

Uses `llama-bench` via `./bench_gguf.sh`. This is the primary benchmark method using GGUF model files.

### Testing Predefined Models

### List Available Models

```bash
./bench_gguf.sh --list                   # All models
./bench_gguf.sh --list --tag gemma       # Filter by tag
./bench_gguf.sh --list --max-params 12B  # Filter by size
```

### Benchmark One Model

```bash
./bench_gguf.sh --model gemma-3-4b                # Default quant (Q4_K_M)
./bench_gguf.sh --model gemma-3-4b --quant Q8_0   # Specific quant
```

### Benchmark All Models

```bash
./bench_gguf.sh --auto    # All that fit in your RAM
./bench_gguf.sh --all     # Everything (needs enough RAM + disk)
```

---

## Testing Custom Models

### Local GGUF File

If you have a GGUF file from LM Studio or downloaded manually:

```bash
./bench_gguf.sh --model-path /path/to/model.gguf
```

### From HuggingFace

```bash
./bench_gguf.sh --custom username/model-GGUF --quant Q4_K_M
```

### Scan for Existing Models

```bash
./bench_gguf.sh --scan   # Finds GGUFs in cache, LM Studio, etc.
```

---

## MLX Benchmarks

Uses `mlx_lm.benchmark` via `./bench_mlx.sh`. MLX is Apple's native ML framework, optimized for Apple Silicon. Typically 2-3x faster than GGUF for text generation.

### Setup

```bash
brew install python@3.12
python3.12 -m venv ~/.venvs/mlx
source ~/.venvs/mlx/bin/activate
pip install mlx-lm
```

### Running MLX Benchmarks

MLX models are downloaded from `mlx-community` on HuggingFace:

```bash
./bench_mlx.sh --repo mlx-community/Qwen3-8B-4bit
./bench_mlx.sh --repo mlx-community/Qwen3.5-4B-4bit --cleanup
./bench_mlx.sh --repo mlx-community/gemma-3-1b-it-4bit
```

Results are saved in `results/{gen}/{variant}/raw/{chip}/mlx/` and appear alongside GGUF results in the tables with a Runtime column.

### GGUF vs MLX

Both use standardized benchmarks measuring the same metrics (pp and tg at fixed token counts). The difference is the runtime and quantization:

- **GGUF** (Q4_K_M): llama.cpp, broader model support
- **MLX** (4-bit): Apple-native, faster on Apple Silicon, some newer models may not be supported yet

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
./bench_gguf.sh --model gemma-3-4b --ngl 99   # All GPU (default, fastest)
./bench_gguf.sh --model gemma-3-4b --ngl 0    # CPU only (slowest)
```

**Rule:** Use `99` unless the model doesn't fit in memory. Then reduce until it loads.

### Flash Attention

Optimized attention computation. Faster and uses less memory.

```bash
./bench_gguf.sh --model gemma-3-4b                   # Enabled (default)
./bench_gguf.sh --model gemma-3-4b --no-flash-attn   # Disabled (for comparison)
```

### Threads (`--threads`)

CPU threads. `0` = auto-detect (usually best).

```bash
./bench_gguf.sh --model gemma-3-4b --threads 4   # Manual
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
./bench_gguf.sh --model gemma-3-4b --sweep
```

### Full Sweep (~96 combinations)

```bash
./bench_gguf.sh --model gemma-3-4b --sweep-full
```

### Output

The sweep reports:
- **Top 5 fastest configs**
- **Max Speed** — absolute fastest
- **Long Context** — fastest with 8K+ context
- **CPU Only** — fallback config

---

## Quality Benchmarks

Speed is easy to measure. Quality (how good the model's output is) is harder. We support two quality metrics:

### Perplexity (WikiText-2)

Measures how much quality is lost from quantization. Lower = better.

```bash
./bench_gguf.sh --model gemma-3-4b --quality
```

This:
1. Downloads WikiText-2 (~2MB, cached)
2. Runs `llama-perplexity` on 50 chunks
3. Reports perplexity score

**Requires** `llama-perplexity` (build llama.cpp from source).

It tells you how much quality you lose from quantization:

```
gemma-3-4b F16:    PPL = 6.2   (baseline)
gemma-3-4b Q8_0:   PPL = 6.3   (barely any loss)
gemma-3-4b Q4_K_M: PPL = 6.8   (small loss, much faster)
gemma-3-4b Q2_K:   PPL = 9.1   (significant loss)
```

### Code Quality (HumanEval+)

Measures actual code generation correctness using [EvalPlus](https://github.com/evalplus/evalplus) — a stricter variant of OpenAI's HumanEval benchmark with more test cases. Unlike perplexity, this tests whether the model can write working code.

**Metric:** pass@1 — fraction of problems solved correctly on the first attempt (0.0–1.0, higher is better).

**Prerequisites:**

```bash
pip install evalplus
```

**Running a single model (GGUF):**

```bash
./bench_quality.sh --model qwen2.5-coder-7b
```

**Running with MLX runtime:**

```bash
./bench_quality.sh --model qwen3-8b --runtime mlx
```

**Batch mode — all coding-tagged models:**

```bash
./bench_quality.sh --tag coding
```

**Interpreting pass@1 scores:**

| Score | Interpretation |
|-------|---------------|
| 0.80+ | Excellent — state-of-the-art for open models |
| 0.60–0.80 | Good — competitive with GPT-3.5 class |
| 0.40–0.60 | Moderate — usable for simple tasks |
| <0.40 | Weak — struggles with standard problems |

**Expected runtime:** 15–25 minutes per 7–14B model (164 HumanEval problems).

> **macOS note:** EvalPlus sets memory limits via `setrlimit`. On macOS this requires `EVALPLUS_MAX_MEMORY_BYTES=-1` to disable the limit — `bench_quality.sh` sets this automatically.

---

## Managing Disk Space

### Check Cache

```bash
./bench_gguf.sh --cache-info
```

### Benchmark with Cleanup

```bash
./bench_gguf.sh --model gemma-3-12b --cleanup         # Delete after bench
./bench_gguf.sh --auto --streaming                     # Download-bench-delete loop
```

### Custom Cache Location

```bash
./bench_gguf.sh --auto --cache-dir /Volumes/External/cache
# Or:
export MAC_LLM_CACHE_DIR=/Volumes/External/cache
```

### Clear Cache

```bash
./bench_gguf.sh --cache-clear
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
3. Smaller model: `./bench_gguf.sh --list --max-params 4B`

### Inconsistent results
- **Plug in** your MacBook
- Close other apps (browsers, Docker, IDEs)
- Wait for thermal cooldown between runs
- Run multiple times — some variance is normal

### "Port 8080 already in use" (quality benchmarks)
A previous server process may still be running:
```bash
lsof -i :8080
kill <PID>
```
Or use a different port: `./bench_quality.sh --model ... --port 8081`

### "Server health check timed out" (quality benchmarks)
The model server didn't start in time. Try:
- A smaller model or lower quant
- Increase context: this check waits 120s for GGUF, 300s for MLX (MLX downloads the model)
- Check if `llama-server` / `mlx_lm.server` is already running on that port

### "EvalPlus setrlimit error"
EvalPlus tries to set memory limits which macOS restricts. This is handled automatically by `bench_quality.sh` via `EVALPLUS_MAX_MEMORY_BYTES=-1`. If you run evalplus directly, set that env var manually:
```bash
EVALPLUS_MAX_MEMORY_BYTES=-1 python -m evalplus.evaluate ...
```

### Incomplete results after Ctrl+C (quality benchmarks)
Partial EvalPlus output may be saved in `evalplus_results/`. Check for orphan server processes:
```bash
ps aux | grep llama-server
ps aux | grep mlx_lm.server
```
Kill any lingering processes before re-running.
