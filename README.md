# Mac LLM Bench

Community-driven benchmark database for running LLMs locally on Apple Silicon Macs.

**Goal:** Build a comprehensive, reproducible performance database so anyone can look up how fast a given LLM runs on their specific MacBook — and find the optimal settings for it.

## How It Works

We use **`llama-bench`** as the core benchmark — it's standardized, content-agnostic, and fully reproducible. It measures raw token processing and generation speed at fixed token counts (pp128, pp256, pp512, tg128, tg256). No custom prompts, no subjectivity, no need to ever re-benchmark if test cases change.

Optionally, **`llama-perplexity`** measures quality loss from quantization using the WikiText-2 dataset — another fixed, public benchmark.

## Quick Start

```bash
git clone https://github.com/user/mac-llm-bench.git
cd mac-llm-bench

# Install dependencies
brew install llama.cpp
pip install huggingface-hub     # for model downloads

# Run a quick smoke test (~1GB download)
./bench.sh --quick

# Benchmark a specific model
./bench.sh --model gemma-3-4b

# Benchmark all models that fit in your RAM
./bench.sh --auto

# Find optimal parameters
./bench.sh --model gemma-3-4b --sweep
```

## What It Measures

| Metric | Source | Description |
|--------|--------|-------------|
| **pp128/pp256/pp512** (tok/s) | `llama-bench` | Prompt processing speed at 128/256/512 tokens |
| **tg128/tg256** (tok/s) | `llama-bench` | Text generation speed at 128/256 tokens |
| **Peak Memory** (GB) | `/usr/bin/time` | Maximum RAM usage |
| **Perplexity** | `llama-perplexity` | Quality metric on WikiText-2 (optional) |

All speed metrics come from `llama-bench` — a standardized, content-agnostic benchmark built into llama.cpp. The test sizes (128/256/512 tokens) are fixed and will never change, so all results are always comparable.

## Benchmark Results

> Results are contributed by the community. See [CONTRIBUTING.md](CONTRIBUTING.md) to add yours.

### Apple M5 (32GB) — MacBook Air

| Model | Quant | pp256 tok/s | tg128 tok/s | Memory GB |
|-------|-------|-------------|-------------|-----------|
| *Run `./bench.sh --auto` to contribute!* |

### Apple M4 Pro (48GB)

| Model | Quant | pp256 tok/s | tg128 tok/s | Memory GB |
|-------|-------|-------------|-------------|-----------|
| *Awaiting contributions* |

### Apple M3 Max (64GB)

| Model | Quant | pp256 tok/s | tg128 tok/s | Memory GB |
|-------|-------|-------------|-------------|-----------|
| *Awaiting contributions* |

## Initial Model Set: Gemma 3

We start with the Gemma 3 family as the initial benchmark set — a clean size ladder (1B, 4B, 12B, 27B) that covers tiny to large models, all ungated (no HuggingFace login required):

| Model | Params | Default Quant | Min RAM |
|-------|--------|---------------|---------|
| gemma-3-1b | 1B | Q4_K_M | 4 GB |
| gemma-3-4b | 4B | Q4_K_M | 4 GB |
| gemma-3-12b | 12B | Q4_K_M | 8 GB |
| gemma-3-27b | 27B | Q4_K_M | 16 GB |

More model families (Llama, Qwen, Mistral, DeepSeek, Phi) can be added by the community via PR. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Parameter Optimization

Beyond raw speed, find the **optimal settings** for each model on your hardware:

```bash
./bench.sh --model gemma-3-4b --sweep        # Quick sweep
./bench.sh --model gemma-3-4b --sweep-full   # Exhaustive sweep
```

Sweeps test combinations of: GPU layers (`-ngl`), context size, batch size, and thread count. The output shows the best config for max speed, long context, and CPU-only operation.

## Documentation

- **[GUIDE.md](GUIDE.md)** — Detailed user guide
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — How to submit results and add models
- **[models.yaml](models.yaml)** — Model registry
- **[schemas/result.schema.json](schemas/result.schema.json)** — Result JSON format

## Requirements

- macOS on Apple Silicon (M1/M2/M3/M4/M5)
- [llama.cpp](https://github.com/ggml-org/llama.cpp) — `brew install llama.cpp`
- [huggingface-hub](https://pypi.org/project/huggingface-hub/) — `pip install huggingface-hub`
- Python 3 (pre-installed on macOS)

## Why llama-bench?

Custom prompts create a comparability problem: change the prompt, and every result in the database becomes invalid. `llama-bench` avoids this entirely — it measures how fast the hardware processes N tokens, regardless of content. The token count is the only variable, and we fix that too (128, 256, 512). Results from today will be directly comparable to results from next year.

## License

MIT
