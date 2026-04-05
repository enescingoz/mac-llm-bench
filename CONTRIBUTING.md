# Contributing to Mac LLM Bench

Every contribution helps build the benchmark database. Whether it's results from your MacBook, a new model family, or a script improvement.

## Table of Contents

- [Submitting Benchmark Results](#submitting-benchmark-results)
- [Adding New Models](#adding-new-models)
- [Result Format](#result-format)
- [Guidelines](#guidelines)

---

## Submitting Benchmark Results

### 1. Run Benchmarks

```bash
git clone https://github.com/user/mac-llm-bench.git
cd mac-llm-bench

# Option A: All Gemma models that fit in RAM (recommended for first contribution)
./bench.sh --auto

# Option B: Specific model
./bench.sh --model gemma-3-4b

# Option C: Low disk space — download, bench, delete, repeat
./bench.sh --auto --streaming

# Option D: Include quality measurement
./bench.sh --model gemma-3-4b --quality
```

### 2. Check Results

```bash
./bench.sh --results
ls results/
```

### 3. Submit PR

```bash
git checkout -b results/your-mac-description
git add results/
git commit -m "Add benchmarks: MacBook Pro M4 Max 64GB"
git push origin results/your-mac-description
# Open PR on GitHub
```

### PR Description Template

```markdown
## Benchmark Results: [Mac Model] [Chip] [RAM]GB

### Hardware
- **Machine**: MacBook Air 2025
- **Chip**: Apple M5
- **RAM**: 32GB
- **OS**: macOS 15.x
- **Power**: AC (plugged in)

### Models Tested
- gemma-3-1b Q4_K_M
- gemma-3-4b Q4_K_M
- gemma-3-12b Q4_K_M
- gemma-3-27b Q4_K_M

### Highlights
- Fastest: gemma-3-1b at X tok/s (tg128)
- Largest tested: gemma-3-27b
```

---

## Adding New Models

We start with Gemma 3 as the initial set, but welcome all model families.

### 1. Add to models.yaml

```yaml
  my-new-model-7b:
    name: "My New Model 7B Instruct"
    params: "7B"
    sources:
      - repo: "bartowski/My-New-Model-7B-Instruct-GGUF"
        gated: false
    quants: [Q3_K_M, Q4_K_M, Q5_K_M, Q6_K, Q8_0]
    default_quant: Q4_K_M
    file_pattern: "My-New-Model-7B-Instruct-{quant}.gguf"
    min_ram: 8
    tags: [provider, size-class, use-case]
```

### 2. Checklist

- [ ] Model ID is lowercase with hyphens
- [ ] At least one ungated source listed first
- [ ] `file_pattern` matches actual HuggingFace filenames (with `{quant}` placeholder)
- [ ] `min_ram` is realistic for default quant
- [ ] You've tested download + benchmark locally
- [ ] Include your benchmark results in the same PR

### 3. Tag Convention

- **Provider**: `google`, `meta`, `qwen`, `mistral`, `microsoft`, `deepseek`
- **Size**: `tiny` (<2B), `small` (2-6B), `medium` (7-15B), `large` (16B+)
- **Use case**: `general`, `coding`, `reasoning`, `chat`

---

## Result Format

Results follow the v2 schema (`schemas/result.schema.json`). Key fields:

```json
{
  "version": "2.0",
  "hardware": { "chip": "Apple M5", "total_ram_gb": 32, ... },
  "model": { "name": "Gemma 3 4B", "quant": "Q4_K_M", ... },
  "speed": {
    "pp128": 250.5,
    "pp256": 245.2,
    "pp512": 238.1,
    "tg128": 42.3,
    "tg256": 41.8
  },
  "memory": { "peak_rss_gb": 3.2 },
  "quality": { "perplexity": 8.45 }
}
```

Speed values come directly from `llama-bench` — standardized and reproducible. Quality (perplexity on WikiText-2) is optional.

---

## Guidelines

### Do
- Run benchmarks **plugged in** for consistent results
- Close resource-heavy apps before benchmarking
- Use **default quant** (Q4_K_M) for the primary result — other quants as bonus
- Note anything unusual (thermal throttling, background processes)
- Test that models download and run before adding to registry

### Don't
- Submit results from virtual machines — Apple Silicon only
- Modify result JSON files by hand (re-run instead)
- Commit GGUF model files (`.gitignore` handles this)

### Commit Messages
```
Add benchmarks: <Mac Model> <Chip> <RAM>GB
Add model: <model-name> to registry
Fix: <description>
```
