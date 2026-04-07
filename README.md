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
| **Apple M5** | [View results](results/m5/) | 1 config, 62 benchmarks (37 GGUF + 25 MLX) |

Each generation page contains separate tables for every variant (base, Pro, Max, Ultra) and hardware configuration (CPU cores, GPU cores, RAM).

> Full results index with cross-generation comparison: [results/README.md](results/README.md)

## Quick Start

```bash
git clone https://github.com/enescingoz/mac-llm-bench.git
cd mac-llm-bench

# GGUF benchmarks (llama.cpp)
brew install llama.cpp
pip3 install huggingface-hub
./bench_gguf.sh --quick                  # Quick smoke test
./bench_gguf.sh --auto                   # All models that fit in RAM

# MLX benchmarks (Apple MLX) - optional, requires Python 3.10+
python3.12 -m venv ~/.venvs/mlx && source ~/.venvs/mlx/bin/activate
pip install mlx-lm
./bench_mlx.sh --repo mlx-community/Qwen3-8B-4bit

# Regenerate result tables
python3 scripts/generate_results.py
```

## How It Works

We support two runtimes, each with its own standardized benchmark:

| Runtime | Benchmark Tool | Script | Model Format |
|---------|---------------|--------|-------------|
| **GGUF** | `llama-bench` | `./bench_gguf.sh` | GGUF (llama.cpp) |
| **MLX** | `mlx_lm.benchmark` | `./bench_mlx.sh` | MLX 4-bit (Apple MLX) |

Both measure the same metrics at fixed token counts (pp128, pp256, pp512, tg128, tg256). Results are stored separately and displayed side-by-side with a Runtime column so you can compare GGUF vs MLX directly.

> **Note:** Some newer models (e.g., Gemma 4) may not yet be supported by all runtimes. MLX support depends on the `mlx-lm` library version. These will be added as runtime support becomes available.

## Supported Models

Currently benchmarking 10 model families (37 GGUF + 25 MLX = 62 benchmarks):

| Family | Models | Sizes |
|--------|--------|-------|
| **Gemma 4** (Google) | 4 models | E2B, E4B, 26B-A4B MoE, 31B |
| **Gemma 3** (Google) | 4 models | 1B, 4B, 12B, 27B |
| **Qwen 3.5** (Alibaba) | 4 models | 4B, 9B, 27B, 35B-A3B MoE |
| **Qwen 3** (Alibaba) | 7 models | 0.6B, 1.7B, 4B, 8B, 14B, 32B, 30B-A3B MoE |
| **Qwen 2.5 Coder** (Alibaba) | 3 models | 7B, 14B, 32B |
| **QwQ** (Alibaba) | 1 model | 32B |
| **DeepSeek R1 Distill** | 3 models | 7B, 14B, 32B |
| **Phi-4** (Microsoft) | 4 models | Mini 3.8B, Mini Reasoning 3.8B, 14B, Reasoning Plus 14B |
| **Mistral** | 4 models | 7B v0.3, Nemo 12B, Small 3.1 24B, Devstral Small 24B |
| **Llama** (Meta) | 3 models | 3.2 1B, 3.2 3B, 3.1 8B |

All ungated — no HuggingFace login required. More model families can be added via PR. Run `./bench_gguf.sh --list` to see all available models.

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
./bench_gguf.sh --model gemma-3-4b --sweep        # Quick sweep
./bench_gguf.sh --model gemma-3-4b --sweep-full   # Exhaustive sweep
```

## Project Structure

```
mac-llm-bench/
├── bench_gguf.sh                   # GGUF benchmark (llama.cpp)
├── bench_mlx.sh                    # MLX benchmark (mlx-lm)
├── models.yaml                     # Model registry
├── requirements.txt                # Python dependencies
├── lib/
│   ├── run_bench_gguf.sh           # llama-bench wrapper
│   ├── run_bench_mlx.sh            # mlx_lm.benchmark wrapper
│   ├── run_sweep_gguf.sh           # GGUF parameter sweep
│   ├── collect_results.sh          # Shared result storage
│   ├── detect_hardware.sh          # Hardware detection
│   ├── download_model.sh           # HuggingFace download
│   └── parse_yaml.py               # YAML parser
├── scripts/
│   └── generate_results.py         # Generates result tables
├── results/
│   ├── README.md                   # Auto-generated index
│   ├── m1/ ... m5/                 # Per-generation results
│   │   ├── README.md               # Auto-generated tables
│   │   └── {variant}/raw/
│   │       └── {chip}_{cpu}c-{gpu}g_{ram}gb/
│   │           ├── gguf/           # GGUF benchmark results
│   │           └── mlx/            # MLX benchmark results
├── schemas/
│   └── result.schema.json          # Result JSON format
├── CONTRIBUTING.md
└── GUIDE.md
```

## Documentation

- **[GUIDE.md](GUIDE.md)** — Detailed user guide for benchmarking
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — How to submit results and add models
- **[results/](results/)** — All benchmark results

## Requirements

**GGUF benchmarks:**
- macOS on Apple Silicon (M1/M2/M3/M4/M5)
- [llama.cpp](https://github.com/ggml-org/llama.cpp) — `brew install llama.cpp`
- [huggingface-hub](https://pypi.org/project/huggingface-hub/) — `pip3 install huggingface-hub`
- Python 3 (pre-installed on macOS)

**MLX benchmarks (optional):**
- Python 3.10+ (install via `brew install python@3.12`)
- [mlx-lm](https://github.com/ml-explore/mlx-lm) — `pip install mlx-lm` (in a venv recommended)

## License

MIT
