# M1 Benchmarks

All speed values are in **tokens/second** from `llama-bench` (higher = better). Memory is peak RSS in GB.

## M1 - 8 CPU / 7 GPU / 16GB

| Model | Runtime | Quant | pp128 | pp256 | pp512 | tg128 | tg256 | Memory |
|-------|---------|-------|------:|------:|------:|------:|------:|-------:|
| Qwen3-0.6B-4bit | MLX | 4bit | 832.2 | 890.3 | 944.8 | 114.7 | 120.5 | 0.82 |
| Qwen 3 0.6B | GGUF | Q4_K_M | 1392.7 | 1436.2 | 1415.1 | 83.3 | 83.3 | 0.57 |
| gemma-3-1b-it-4bit | MLX | 4bit | 854.2 | 962.8 | 1042.4 | 81.4 | 81.3 | 1.08 |
| Llama 3.2 1B Instruct | GGUF | Q4_K_M | 753.7 | 776.9 | 772.9 | 64.8 | 65.1 | 0.86 |
| Qwen 3 1.7B | GGUF | Q4_K_M | 507.8 | 520.4 | 516.7 | 43.4 | 43.7 | 1.31 |
| Gemma 3 1B | GGUF | Q4_K_M | 885.5 | 936.0 | 950.8 | 42.0 | 42.8 | 0.85 |
| Gemma 4 E2B | GGUF | Q4_K_M | 369.8 | 375.2 | 374.9 | 27.4 | 27.3 | 3.39 |
| Llama 3.2 3B Instruct | GGUF | Q4_K_M | 266.0 | 270.0 | 268.2 | 27.0 | 25.9 | 2.01 |
| Qwen3.5-4B-4bit | MLX | 4bit | 118.0 | 125.2 | 128.7 | 23.2 | 23.3 | 3.16 |
| Gemma 3 4B | GGUF | Q4_K_M | 231.1 | 235.0 | 235.3 | 21.3 | 20.7 | 2.45 |
| Phi 4 Mini 3.8B | GGUF | Q4_K_M | 226.7 | 226.6 | 220.2 | 20.8 | 19.9 | 2.45 |
| Qwen 3 4B | GGUF | Q4_K_M | 205.6 | 206.9 | 206.2 | 20.4 | 19.4 | 2.45 |
| Phi 4 Mini Reasoning 3.8B | GGUF | Q4_K_M | 210.8 | 210.3 | 209.0 | 19.9 | 18.4 | 2.45 |
| Gemma 4 E4B | GGUF | Q4_K_M | 182.4 | 185.0 | 183.2 | 15.9 | 15.2 | 5.21 |
| Qwen 3.5 4B | GGUF | Q4_K_M | 182.0 | 185.3 | 178.8 | 14.1 | 13.5 | 2.74 |
| Qwen3-8B-4bit | MLX | 4bit | 65.5 | 68.1 | 67.8 | 12.5 | 12.8 | 5.12 |
| DeepSeek R1 Distill 7B | GGUF | Q4_K_M | 106.7 | 106.1 | 100.6 | 11.5 | 11.1 | 4.47 |
| Qwen 3 8B | GGUF | Q4_K_M | 98.2 | 97.6 | 94.1 | 11.0 | 10.8 | 4.81 |
| Qwen 3.5 9B | GGUF | Q4_K_M | 91.6 | 91.3 | 86.8 | 8.3 | 8.2 | 5.48 |
| Gemma 3 12B | GGUF | Q4_K_M | 56.7 | 59.3 | 57.2 | 6.7 | 6.6 | 6.99 |

---

*Auto-generated from raw benchmark data in [`raw/`](raw/). Run `python3 scripts/generate_results.py` to regenerate.*