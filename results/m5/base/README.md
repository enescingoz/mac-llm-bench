# M5 Benchmarks

All speed values are in **tokens/second** from `llama-bench` (higher = better). Memory is peak RSS in GB.

## M5 - 10 CPU / 10 GPU / 32GB

| Model | Quant | pp128 | pp256 | pp512 | tg128 | tg256 | Memory |
|-------|-------|------:|------:|------:|------:|------:|-------:|
| Gemma 3 1B | Q4_K_M | 1753.8 | 1431.1 | 1488.8 | 46.6 | 46.6 | 0.86 |
| Gemma 3 4B | Q4_K_M | 326.1 | 318.0 | 304.5 | 16.5 | 16.6 | 2.46 |
| Gemma 3 12B | Q4_K_M | 102.0 | 101.4 | 99.8 | 5.7 | 5.5 | 7.00 |
| Gemma 3 27B | Q4_K_M | 48.6 | 50.1 | 50.7 | 3.0 | 2.9 | 15.64 |

---

*Auto-generated from raw benchmark data in [`raw/`](raw/). Run `python3 scripts/generate_results.py` to regenerate.*