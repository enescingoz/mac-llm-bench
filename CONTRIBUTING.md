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

# Option A: All models that fit in RAM (recommended)
./bench.sh --auto

# Option B: Specific model
./bench.sh --model gemma-3-4b

# Option C: Low disk space — download, bench, delete, repeat
./bench.sh --auto --streaming
```

### 2. Regenerate Tables

```bash
python3 scripts/generate_results.py
```

This reads all raw JSON files and regenerates the README.md tables in each `results/{generation}/` folder.

### 3. Check Results

```bash
./bench.sh --results
```

Your results are saved as JSON in:
```
results/{generation}/raw/{chip}_{cpu}c-{gpu}g_{ram}gb/
```

For example:
```
results/m5/raw/m5_10c-10g_32gb/gemma-3-4b_Q4_K_M_ngl99.json
results/m4/raw/m4-pro_14c-20g_48gb/gemma-3-12b_Q4_K_M_ngl99.json
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
```

---

## How Results Are Organized

```
results/
├── README.md                          ← Auto-generated index
├── m1/
│   ├── README.md                      ← Auto-generated tables for all M1 variants
│   └── raw/
│       ├── m1_8c-7g_8gb/             ← M1, 8 CPU, 7 GPU, 8GB
│       │   ├── gemma-3-1b_Q4_K_M_ngl99.json
│       │   └── gemma-3-4b_Q4_K_M_ngl99.json
│       └── m1-pro_10c-16g_32gb/      ← M1 Pro, 10 CPU, 16 GPU, 32GB
│           └── ...
├── m2/
│   ├── README.md
│   └── raw/ ...
├── m3/ ...
├── m4/ ...
└── m5/
    ├── README.md
    └── raw/
        └── m5_10c-10g_32gb/
            ├── gemma-3-1b_Q4_K_M_ngl99.json
            ├── gemma-3-4b_Q4_K_M_ngl99.json
            ├── gemma-3-12b_Q4_K_M_ngl99.json
            └── gemma-3-27b_Q4_K_M_ngl99.json
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
| `results/*/raw/**/*.json` | `bench.sh` (you run it) | Yes — this is your contribution |
| `results/*/README.md` | `generate_results.py` | Yes — regenerated from raw data |
| `results/README.md` | `generate_results.py` | Yes — regenerated from raw data |

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
