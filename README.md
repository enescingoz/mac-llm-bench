# Mac LLM Bench

Community-driven benchmark database for running LLMs locally on Apple Silicon Macs. Speed + code quality benchmarks for LLMs on Apple Silicon.

**Goal:** Build a comprehensive, reproducible performance database so anyone can look up how fast a given LLM runs on their specific Mac — and find the optimal settings for it.

## Benchmark Results

Browse results by chip generation:

| Generation | Link | Status |
|------------|------|--------|
| **Apple M1** | [View results](results/m1/) | Awaiting contributions |
| **Apple M2** | [View results](results/m2/) | 1 config (M2 Max), 38 GGUF + 1 MLX |
| **Apple M3** | [View results](results/m3/) | Awaiting contributions |
| **Apple M4** | [View results](results/m4/) | Awaiting contributions |
| **Apple M5** | [View results](results/m5/) | 1 config, 62 benchmarks (37 GGUF + 25 MLX) |

Each generation page contains separate tables for every variant (base, Pro, Max, Ultra) and hardware configuration (CPU cores, GPU cores, RAM).

> Full results index with cross-generation comparison: [results/README.md](results/README.md)

## Quick Start

```bash
git clone https://github.com/enescingoz/mac-llm-bench.git
cd mac-llm-bench

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# For GGUF benchmarks, also install llama.cpp
brew install llama.cpp

# GGUF benchmarks
./bench_gguf.sh --quick                  # Quick smoke test
./bench_gguf.sh --auto                   # All models that fit in RAM

# MLX benchmarks (Apple MLX)
./bench_mlx.sh --repo mlx-community/Qwen3-8B-4bit

# Quality benchmark (HumanEval+ code evaluation)
./bench_quality.sh --model qwen2.5-coder-7b

# Regenerate result tables
python3 scripts/generate_results.py
```

> **Note:** Always activate the virtual environment (`source .venv/bin/activate`) before running any bench scripts.

## How It Works

We support two runtimes, each with its own standardized benchmark:

| Runtime | Benchmark Tool | Script | Model Format | Default Quant |
|---------|---------------|--------|-------------|--------------|
| **GGUF** | `llama-bench` | `./bench_gguf.sh` | GGUF (llama.cpp) | Q4_K_M |
| **MLX** | `mlx_lm.benchmark` | `./bench_mlx.sh` | MLX (Apple MLX) | 4-bit |
| **Quality** | EvalPlus (HumanEval+) | `./bench_quality.sh` | GGUF or MLX | same as above |

Both measure the same metrics at fixed token counts (pp128, pp256, pp512, tg128, tg256). Results are stored separately and displayed side-by-side with a Runtime column so you can compare GGUF vs MLX directly.

> **Note:** Some newer models (e.g., Gemma 4) may not yet be supported by all runtimes. MLX support depends on the `mlx-lm` library version. These will be added as runtime support becomes available.

## Methodology

All published results follow these fixed conditions so results are comparable across submissions.

**Quantization**

- GGUF models: Q4_K_M quantization via llama.cpp
- MLX models: 4-bit quantization via mlx-lm

**Speed benchmarks**

- Tool: `llama-bench` (GGUF) / `mlx_lm.benchmark` (MLX)
- Metrics: prompt processing and text generation at fixed token counts (pp128, pp256, pp512, tg128, tg256)
- All GPU layers offloaded (`ngl=99`), flash attention enabled
- Context window: 4096 tokens (8192 for reasoning models, with `--no-think` to disable chain-of-thought)

**Quality benchmarks**

- Tool: EvalPlus v0.3.1
- Dataset: HumanEval+ (164 problems with 80x expanded test cases)
- Metric: pass@1 (greedy decoding, temperature=0)
- Single hardware configuration: M5 base 32GB

### Library Versions

Results on this repo were collected with:

| Library | Version |
|---------|---------|
| llama.cpp | build 8680 (brew stable) |
| mlx-lm | 0.31.2 |
| EvalPlus | 0.3.1 |
| Python | 3.12 |

Version strings are also stored in each result JSON under `runtime.version` for full reproducibility.

## Supported Models

Currently benchmarking 10 model families (100 total benchmarks across 2 chips):

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

> **Quality benchmarks:** Models tagged `coding` (Qwen 2.5 Coder, Devstral, etc.) support HumanEval+ evaluation via `./bench_quality.sh`.

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
├── bench_quality.sh                # Quality benchmark (EvalPlus HumanEval+)
├── models.yaml                     # Model registry
├── requirements.txt                # Python dependencies
├── lib/
│   ├── run_bench_gguf.sh           # llama-bench wrapper
│   ├── run_bench_mlx.sh            # mlx_lm.benchmark wrapper
│   ├── run_sweep_gguf.sh           # GGUF parameter sweep
│   ├── run_quality_gguf.sh         # Quality benchmark GGUF runner
│   ├── run_quality_mlx.sh          # Quality benchmark MLX runner
│   ├── parse_evalplus.py           # EvalPlus result parser
│   ├── merge_quality_result.py     # Merges quality scores into result JSON
│   ├── collect_results.sh          # Shared result storage
│   ├── detect_hardware.sh          # Hardware detection
│   ├── download_model.sh           # HuggingFace download
│   └── parse_yaml.py               # YAML parser
├── scripts/
│   └── generate_results.py         # Generates result tables
├── results/
│   ├── README.md                   # Auto-generated index
│   ├── m1/ ... m5/                 # Per-generation results
│   │   ├── README.md               # Auto-generated generation overview
│   │   └── {variant}/
│   │       ├── README.md           # Combined speed + quality overview
│   │       ├── speed/
│   │       │   └── README.md       # Speed-only leaderboard
│   │       ├── quality/
│   │       │   ├── coding/
│   │       │   │   └── README.md   # HumanEval+ results
│   │       │   ├── reasoning/
│   │       │   │   └── README.md   # Placeholder (GSM8K, ARC — coming soon)
│   │       │   └── general/
│   │       │       └── README.md   # Placeholder (MMLU, HellaSwag — coming soon)
│   │       └── raw/
│   │           └── {chip}_{cpu}c-{gpu}g_{ram}gb/
│   │               ├── gguf/       # GGUF benchmark results (*.json)
│   │               └── mlx/        # MLX benchmark results (*.json)
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

**All benchmarks:**
- macOS on Apple Silicon (M1/M2/M3/M4/M5)
- Python 3.10+ — `brew install python@3.12`
- Project `.venv` with `pip install -r requirements.txt` (includes mlx-lm, evalplus, huggingface-hub, pyyaml, pandas, pyarrow)

**GGUF benchmarks:**
- [llama.cpp](https://github.com/ggml-org/llama.cpp) — `brew install llama.cpp`

## Known Limitations

- **HumanEval+ scope:** HumanEval+ measures algorithmic problem-solving ability on 164 self-contained coding problems. It does not test production code quality, repo-level context handling, or architectural awareness. Scores should not be read as a measure of real-world coding assistant capability.
- **Single quantization level:** All models are tested at Q4_K_M (GGUF) or 4-bit (MLX). Results at other quantization levels will differ, particularly for perplexity and quality scores.
- **Gemma 4 results:** Gemma 4 models score unusually low on quality benchmarks. This is likely caused by a known tool-calling bug in llama.cpp that causes premature inference stopping, not actual model capability. Treat these results with caution until the bug is resolved.
- **Reasoning models tested without chain-of-thought:** Qwen 3.x, QwQ, and DeepSeek R1 models are tested with `--no-think`, which disables chain-of-thought reasoning. This may understate their quality ceiling.
- **Single hardware configuration for quality benchmarks:** Quality scores are currently collected only on M5 base 32GB. Speed results cover more hardware configurations.

## License

MIT
