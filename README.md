# Mac LLM Bench

Community-driven benchmark database for running LLMs locally on Apple Silicon Macs.

**Goal:** Build a comprehensive, reproducible performance database so anyone can look up how fast a given LLM runs on their specific Mac — and find the optimal settings for it.

## Benchmark Results

Browse results by chip generation:

| Generation | Link | Status |
|------------|------|--------|
| **Apple M1** | [View results](results/m1/) | Awaiting contributions |
| **Apple M2** | [View results](results/m2/) | Awaiting contributions |
| **Apple M3** | [View results](results/m3/) | Awaiting contributions |
| **Apple M4** | [View results](results/m4/) | Awaiting contributions |
| **Apple M5** | [View results](results/m5/) | 1 config, 4 models |

Each generation page contains separate tables for every variant (base, Pro, Max, Ultra) and hardware configuration (CPU cores, GPU cores, RAM).

> Full results index with cross-generation comparison: [results/README.md](results/README.md)

## Quick Start

```bash
git clone https://github.com/enescingoz/mac-llm-bench.git
cd mac-llm-bench

# Install dependencies
brew install llama.cpp
pip3 install huggingface-hub

# Run a quick smoke test (~0.8GB download)
./bench.sh --quick

# Benchmark all models that fit in your RAM
./bench.sh --auto

# Regenerate result tables after benchmarking
python3 scripts/generate_results.py
```

## How It Works

We use **`llama-bench`** as the core benchmark — standardized, content-agnostic, and fully reproducible. It measures raw token processing and generation speed at fixed token counts (pp128, pp256, pp512, tg128, tg256). No custom prompts, no subjectivity, no need to ever re-benchmark if test cases change.

| Metric | Source | Description |
|--------|--------|-------------|
| **pp128/pp256/pp512** (tok/s) | `llama-bench` | Prompt processing speed |
| **tg128/tg256** (tok/s) | `llama-bench` | Text generation speed |
| **Peak Memory** (GB) | `/usr/bin/time` | Maximum RAM usage |
| **Perplexity** | `llama-perplexity` | Quality on WikiText-2 (optional) |

## Initial Model Set: Gemma 3

| Model | Params | Default Quant | Min RAM |
|-------|--------|---------------|---------|
| gemma-3-1b | 1B | Q4_K_M | 4 GB |
| gemma-3-4b | 4B | Q4_K_M | 4 GB |
| gemma-3-12b | 12B | Q4_K_M | 8 GB |
| gemma-3-27b | 27B | Q4_K_M | 16 GB |

All ungated — no HuggingFace login required. More model families can be added via PR.

## Apple Silicon Coverage

We aim to cover every Apple Silicon configuration:

```
M1 / M2 / M3 / M4 / M5
  × base / Pro / Max / Ultra
    × various CPU/GPU core counts
      × various RAM sizes (8GB – 256GB)
```

Results are organized by generation → variant → hardware config. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add your machine.

## Parameter Optimization

Find optimal settings for each model on your hardware:

```bash
./bench.sh --model gemma-3-4b --sweep        # Quick sweep
./bench.sh --model gemma-3-4b --sweep-full   # Exhaustive sweep
```

## Project Structure

```
mac-llm-bench/
├── bench.sh                        # Main CLI
├── models.yaml                     # Model registry
├── requirements.txt                # Python dependencies
├── lib/                            # Benchmark scripts
├── scripts/
│   └── generate_results.py         # Generates result tables from raw data
├── results/
│   ├── README.md                   # Auto-generated index
│   ├── m1/ ... m5/                 # Per-generation results
│   │   ├── README.md               # Auto-generated tables
│   │   └── raw/                    # Raw JSON benchmark data
│   │       └── {chip}_{cpu}c-{gpu}g_{ram}gb/
│   │           └── {model}_{quant}_ngl{n}.json
├── schemas/
│   └── result.schema.json          # Result JSON format
├── CONTRIBUTING.md                  # How to submit results
└── GUIDE.md                        # User guide
```

## Documentation

- **[GUIDE.md](GUIDE.md)** — Detailed user guide for benchmarking
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — How to submit results and add models
- **[results/](results/)** — All benchmark results

## Requirements

- macOS on Apple Silicon (M1/M2/M3/M4/M5)
- [llama.cpp](https://github.com/ggml-org/llama.cpp) — `brew install llama.cpp`
- [huggingface-hub](https://pypi.org/project/huggingface-hub/) — `pip3 install huggingface-hub`
- Python 3 (pre-installed on macOS)

## License

MIT
