# Benchmark Results

Community-contributed benchmark results for LLMs on Apple Silicon.

Browse by chip generation, then select your variant (base, Pro, Max, Ultra).

| Generation | Variants with Data | Total Configs | Total Models | Link |
|------------|--------------------|---------------|--------------|------|
| **M1** | 1 | 1 | 20 | [View results](m1/) |
| **M2** | 1 | 1 | 39 | [View results](m2/) |
| **M3** | - | - | - | [Awaiting contributions](m3/) |
| **M4** | - | - | - | [Awaiting contributions](m4/) |
| **M5** | 1 | 1 | 62 | [View results](m5/) |

## Quick Comparison

Best `tg128` (text generation, tok/s) per generation:

| Model | M1 | M2 | M3 | M4 | M5 |
|-------|------:|------:|------:|------:|------:|
| DeepSeek R1 Distill 14B | - | 18.9 | - | - | 5.6 |
| DeepSeek R1 Distill 32B | - | 8.6 | - | - | 2.6 |
| DeepSeek R1 Distill 7B | 11.5 | 37.4 | - | - | 11.4 |
| DeepSeek-R1-Distill-Qwen-14B-4bit | - | - | - | - | 10.8 |
| DeepSeek-R1-Distill-Qwen-32B-MLX-4Bit | - | - | - | - | 4.8 |
| DeepSeek-R1-Distill-Qwen-7B-4bit-mlx | - | - | - | - | 26.2 |
| Devstral Small 24B | - | 12.3 | - | - | 3.5 |
| Devstral-Small-2-24B-Instruct-2512-4bit | - | - | - | - | 6.6 |
| Gemma 3 12B | 6.7 | 23.3 | - | - | 5.7 |
| Gemma 3 1B | 42.0 | 151.3 | - | - | 46.6 |
| Gemma 3 27B | - | 10.2 | - | - | 3.0 |
| Gemma 3 4B | 21.3 | 65.0 | - | - | 16.5 |
| Gemma 4 26B-A4B MoE | - | 51.6 | - | - | 16.2 |
| Gemma 4 31B | - | 8.4 | - | - | 5.5 |
| Gemma 4 E2B | 27.4 | 88.9 | - | - | 29.2 |
| Gemma 4 E4B | 15.9 | 50.2 | - | - | 36.7 |
| Llama 3.1 8B Instruct | - | 37.5 | - | - | 10.8 |
| Llama 3.2 1B Instruct | 64.8 | 205.9 | - | - | 59.4 |
| Llama 3.2 3B Instruct | 27.0 | 84.7 | - | - | 24.1 |
| Llama-3.2-1B-Instruct-4bit | - | - | - | - | 156.7 |
| Llama-3.2-3B-Instruct-4bit | - | - | - | - | 63.1 |
| Meta-Llama-3.1-8B-Instruct-4bit | - | - | - | - | 28.3 |
| Mistral 7B Instruct v0.3 | - | 39.8 | - | - | 11.5 |
| Mistral Nemo 12B | - | 24.7 | - | - | 6.9 |
| Mistral Small 3.1 24B | - | 12.4 | - | - | 3.6 |
| Mistral-7B-Instruct-v0.3-4bit | - | - | - | - | 22.9 |
| Mistral-Nemo-Instruct-2407-4bit | - | - | - | - | 13.4 |
| Mistral-Small-3.1-Text-24B-Instruct-2503-4bit | - | - | - | - | 6.9 |
| Phi 4 14B | - | 19.4 | - | - | 5.3 |
| Phi 4 Mini 3.8B | 20.8 | 67.8 | - | - | 19.6 |
| Phi 4 Mini Reasoning 3.8B | 19.9 | 68.5 | - | - | 19.4 |
| Phi 4 Reasoning Plus 14B | - | 19.4 | - | - | 5.7 |
| Phi-4-mini-instruct-4bit | - | - | - | - | 52.0 |
| QwQ 32B | - | 9.0 | - | - | 2.6 |
| QwQ-32B-4bit | - | - | - | - | 4.4 |
| Qwen 2.5 Coder 14B | - | 20.4 | - | - | 5.9 |
| Qwen 2.5 Coder 32B | - | 8.9 | - | - | 2.5 |
| Qwen 2.5 Coder 7B | - | 39.1 | - | - | 11.3 |
| Qwen 3 0.6B | 83.3 | 256.1 | - | - | 91.9 |
| Qwen 3 1.7B | 43.4 | 144.4 | - | - | 37.3 |
| Qwen 3 14B | - | 20.3 | - | - | 5.8 |
| Qwen 3 30B-A3B MoE | - | 66.0 | - | - | 23.1 |
| Qwen 3 32B | - | 9.0 | - | - | 2.5 |
| Qwen 3 4B | 20.4 | 65.2 | - | - | 16.5 |
| Qwen 3 8B | 11.0 | 37.2 | - | - | 9.1 |
| Qwen 3.5 27B | - | 9.4 | - | - | 4.4 |
| Qwen 3.5 35B-A3B MoE | - | 45.4 | - | - | 31.3 |
| Qwen 3.5 4B | 14.1 | 48.4 | - | - | 29.4 |
| Qwen 3.5 9B | 8.3 | 30.2 | - | - | 13.2 |
| Qwen2.5-Coder-14B-Instruct-4bit | - | - | - | - | 10.9 |
| Qwen2.5-Coder-32B-Instruct-4bit | - | - | - | - | 4.8 |
| Qwen2.5-Coder-7B-Instruct-4bit | - | - | - | - | 23.5 |
| Qwen3-0.6B-4bit | 114.7 | - | - | - | 259.1 |
| Qwen3-8B-4bit | 12.5 | 48.1 | - | - | 24.0 |
| Qwen3-Coder-30B-A3B-Instruct-4bit | - | 78.0 | - | - | - |
| Qwen3.5-35B-A3B-4bit | - | - | - | - | 58.8 |
| Qwen3.5-4B-4bit | 23.2 | - | - | - | 48.7 |
| Qwen3.5-9B-MLX-4bit | - | - | - | - | 21.5 |
| gemma-3-12b-it-4bit | - | - | - | - | 12.5 |
| gemma-3-1b-it-4bit | 81.4 | - | - | - | 176.7 |
| gemma-3-27b-it-4bit | - | - | - | - | 5.5 |
| gemma-3-4b-it-4bit | - | - | - | - | 53.3 |
| phi-4-4bit | - | - | - | - | 11.6 |

*Best tg128 across all variants within each generation.*

---

*Auto-generated — run `python3 scripts/generate_results.py` to regenerate.*