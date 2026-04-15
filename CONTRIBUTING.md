# Contributing to Mac LLM Bench

Every contribution helps build the benchmark database. Whether it's results from your Mac, a new model family, or a script improvement.

## Table of Contents

- [Submitting Benchmark Results](#submitting-benchmark-results)
- [How Results Are Organized](#how-results-are-organized)
- [Adding New Models](#adding-new-models)
- [Guidelines](#guidelines)

---

## Submitting Benchmark Results

### 1. Run Benchmarks

```bash
git clone https://github.com/enescingoz/mac-llm-bench.git
cd mac-llm-bench

# GGUF benchmarks (llama.cpp)
./bench_gguf.sh --auto                   # All models that fit in RAM
./bench_gguf.sh --model gemma-3-4b       # Specific model
./bench_gguf.sh --auto --streaming       # Low disk space mode

# MLX benchmarks (optional, requires Python 3.10+)
python3.12 -m venv ~/.venvs/mlx && source ~/.venvs/mlx/bin/activate && pip install mlx-lm
./bench_mlx.sh --repo mlx-community/Qwen3-8B-4bit --cleanup

# Optional: Quality benchmarks (coding models only)
./bench_quality.sh --model qwen2.5-coder-7b
```

> **Note:** Quality benchmarks (HumanEval+) are optional. Speed results are always required.

### 2. Regenerate Tables

```bash
python3 scripts/generate_results.py
```

This reads all raw JSON files and regenerates all README.md files under `results/`. For each variant it produces:
- `results/{gen}/{variant}/README.md` — combined speed + quality overview
- `results/{gen}/{variant}/speed/README.md` — speed-only leaderboard
- `results/{gen}/{variant}/quality/coding/README.md` — HumanEval+ results (if any)

### 3. Check Results

```bash
./bench_gguf.sh --results
```

Your results are saved as JSON in:
```
results/{generation}/{variant}/raw/{chip}_{cpu}c-{gpu}g_{ram}gb/{runtime}/
```

For example:
```
results/m5/base/raw/m5_10c-10g_32gb/gguf/gemma-3-4b_Q4_K_M_ngl99.json
results/m4/pro/raw/m4-pro_14c-20g_48gb/gguf/gemma-3-12b_Q4_K_M_ngl99.json
results/m5/base/raw/m5_10c-10g_32gb/mlx/Qwen3-8B-4bit_4bit_ngl99.json
```

The folder name is auto-detected from your hardware — you don't need to name it manually.

### 4. Submit PR

```bash
git checkout -b results/your-chip-description
git add results/
git commit -m "Add benchmarks: M4 Pro 14c/20g 48GB"
git push origin results/your-chip-description
# Open PR on GitHub
```

### PR Description Template

```markdown
## Benchmark Results: [Chip] [CPU]c/[GPU]g [RAM]GB

### Hardware
- **Chip**: Apple M4 Pro
- **CPU/GPU**: 14 cores / 20 GPU cores
- **RAM**: 48GB
- **OS**: macOS 15.x
- **Power**: AC (plugged in)

### Models Tested
- gemma-3-1b Q4_K_M
- gemma-3-4b Q4_K_M
- gemma-3-12b Q4_K_M
- gemma-3-27b Q4_K_M

### Quality Scores (optional — coding models only)
| Model | HumanEval+ pass@1 |
|-------|------------------|
| qwen2.5-coder-7b Q4_K_M | 0.xx |
```

---

## How Results Are Organized

```
results/
├── README.md                          ← Auto-generated index
├── m1/
│   ├── README.md                      ← Auto-generated generation overview
│   └── base/
│       ├── README.md                  ← Combined speed + quality overview
│       ├── speed/
│       │   └── README.md              ← Speed-only leaderboard
│       ├── quality/
│       │   ├── coding/
│       │   │   └── README.md          ← HumanEval+ results
│       │   ├── reasoning/
│       │   │   └── README.md          ← Placeholder (coming soon)
│       │   └── general/
│       │       └── README.md          ← Placeholder (coming soon)
│       └── raw/
│           └── m1_8c-7g_8gb/
│               ├── gguf/              ← GGUF benchmark results
│               │   └── gemma-3-1b_Q4_K_M_ngl99.json
│               └── mlx/               ← MLX benchmark results
│                   └── gemma-3-1b-4bit_4bit_ngl99.json
├── m5/
│   ├── README.md
│   └── base/
│       ├── README.md
│       ├── speed/README.md
│       ├── quality/coding/README.md
│       └── raw/
│           └── m5_10c-10g_32gb/
│               ├── gguf/
│               │   ├── gemma-3-1b_Q4_K_M_ngl99.json
│               │   └── ...
│               └── mlx/
│                   ├── Qwen3-0.6B-4bit_4bit_ngl99.json
│                   └── ...
```

### Folder Naming Convention

```
{generation}-{variant}_{cpu}c-{gpu}g_{ram}gb
```

- **Base chips**: `m5_10c-10g_32gb` (no variant suffix)
- **Pro/Max/Ultra**: `m4-pro_14c-20g_48gb`, `m3-max_16c-40g_128gb`

This is auto-detected — the script reads your hardware and creates the right folder.

### What You Contribute vs What's Generated

| File | Who creates it | Committed? |
|------|---------------|------------|
| `results/**/raw/**/gguf/*.json` | `bench_gguf.sh` (you run it) | Yes — your contribution |
| `results/**/raw/**/mlx/*.json` | `bench_mlx.sh` (you run it) | Yes — your contribution |
| `results/{gen}/{variant}/README.md` | `generate_results.py` | Yes — regenerated |
| `results/{gen}/{variant}/speed/README.md` | `generate_results.py` | Yes — regenerated |
| `results/{gen}/{variant}/quality/*/README.md` | `generate_results.py` | Yes — regenerated |
| `results/{gen}/README.md` | `generate_results.py` | Yes — regenerated |
| `results/README.md` | `generate_results.py` | Yes — regenerated |

**Never edit README.md files in `results/` manually** — they get overwritten by the generator.

---

## Adding New Models

### 1. Add to models.yaml

```yaml
  my-model-7b:
    name: "My Model 7B Instruct"
    params: "7B"
    sources:
      - repo: "bartowski/My-Model-7B-Instruct-GGUF"
        gated: false
    quants: [Q3_K_M, Q4_K_M, Q5_K_M, Q6_K, Q8_0]
    default_quant: Q4_K_M
    file_pattern: "My-Model-7B-Instruct-{quant}.gguf"
    min_ram: 8
    tags: [provider, size-class, use-case]
```

### 2. Checklist

- [ ] Model ID is lowercase with hyphens
- [ ] At least one ungated source listed first
- [ ] `file_pattern` matches actual filenames on HuggingFace (with `{quant}` placeholder)
- [ ] `min_ram` is realistic for default quant
- [ ] Tested download + benchmark locally
- [ ] Include your benchmark results in the same PR

### 3. Tag Convention

- **Provider**: `google`, `meta`, `qwen`, `mistral`, `microsoft`, `deepseek`
- **Size**: `tiny` (<2B), `small` (2-6B), `medium` (7-15B), `large` (16B+)
- **Use case**: `general`, `coding`, `reasoning`, `chat`

---

## Guidelines

### Do
- Run benchmarks **plugged in** for consistent results
- Close resource-heavy apps before benchmarking
- Run `python3 scripts/generate_results.py` before committing
- Use **default quant** (Q4_K_M) for primary results
- Note anything unusual (thermal throttling, etc.)

### Don't
- Edit `README.md` files in `results/` — they're auto-generated
- Submit results from virtual machines — Apple Silicon only
- Modify result JSON files by hand
- Commit GGUF model files

### Commit Messages
```
Add benchmarks: M5 10c/10g 32GB
Add benchmarks: M4 Pro 14c/20g 48GB
Add model: <model-name> to registry
Fix: <description>
```
