# M5 Benchmarks

All speed values are in **tokens/second** from `llama-bench` (higher = better). Memory is peak RSS in GB.

## M5 - 10 CPU / 10 GPU / 32GB

| Model | Quant | pp128 | pp256 | pp512 | tg128 | tg256 | Memory |
|-------|-------|------:|------:|------:|------:|------:|-------:|
| Qwen 3 0.6B | Q4_K_M | 4840.2 | 2012.9 | 1977.8 | 91.9 | 89.8 | 0.57 |
| Gemma 3 1B | Q4_K_M | 1753.8 | 1431.1 | 1488.8 | 46.6 | 46.6 | 0.86 |
| Qwen 3 1.7B | Q4_K_M | 900.9 | 773.6 | 774.5 | 37.3 | 37.5 | 1.32 |
| Qwen 3 30B-A3B MoE | Q4_K_M | 217.0 | 282.6 | 340.3 | 23.1 | 23.5 | 17.48 |
| Phi 4 Mini 3.8B | Q4_K_M | 378.9 | 384.9 | 380.3 | 19.6 | 19.6 | 2.46 |
| Phi 4 Mini Reasoning 3.8B | Q4_K_M | 447.2 | 392.9 | 380.7 | 19.4 | 19.5 | 2.46 |
| Gemma 3 4B | Q4_K_M | 326.1 | 318.0 | 304.5 | 16.5 | 16.6 | 2.46 |
| Qwen 3 4B | Q4_K_M | 296.5 | 290.8 | 283.8 | 16.5 | 16.4 | 2.46 |
| DeepSeek R1 Distill 7B | Q4_K_M | 195.6 | 190.8 | 194.1 | 11.4 | 12.1 | 4.47 |
| Qwen 3 8B | Q4_K_M | 157.0 | 153.0 | 153.8 | 9.1 | 9.2 | 4.81 |
| Qwen 3 14B | Q4_K_M | 84.5 | 84.8 | 94.4 | 5.8 | 5.6 | 8.52 |
| Gemma 3 12B | Q4_K_M | 102.0 | 101.4 | 99.8 | 5.7 | 5.5 | 7.00 |
| Phi 4 Reasoning Plus 14B | Q4_K_M | 92.1 | 92.8 | 87.5 | 5.7 | 5.7 | 8.56 |
| DeepSeek R1 Distill 14B | Q4_K_M | 97.3 | 96.5 | 89.6 | 5.6 | 5.7 | 8.52 |
| Phi 4 14B | Q4_K_M | 86.8 | 83.7 | 79.7 | 5.3 | 5.4 | 8.56 |
| Gemma 3 27B | Q4_K_M | 48.6 | 50.1 | 50.7 | 3.0 | 2.9 | 15.64 |
| DeepSeek R1 Distill 32B | Q4_K_M | 42.8 | 40.0 | 38.8 | 2.6 | 2.5 | 18.65 |
| Qwen 3 32B | Q4_K_M | 42.6 | 42.1 | 41.4 | 2.5 | 2.6 | 18.57 |

---

*Auto-generated from raw benchmark data in [`raw/`](raw/). Run `python3 scripts/generate_results.py` to regenerate.*