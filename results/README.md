# Benchmark Results

Community-contributed benchmark results for LLMs on Apple Silicon.

Browse by chip generation, then select your variant (base, Pro, Max, Ultra).

| Generation | Variants with Data | Total Configs | Total Models | Link |
|------------|--------------------|---------------|--------------|------|
| **M1** | - | - | - | [Awaiting contributions](m1/) |
| **M2** | 1 | 1 | 38 | [View results](m2/) |
| **M3** | - | - | - | [Awaiting contributions](m3/) |
| **M4** | - | - | - | [Awaiting contributions](m4/) |
| **M5** | 1 | 1 | 62 | [View results](m5/) |

## Quick Comparison

Best `tg128` (text generation, tok/s) per generation:

| Model | M1 | M2 | M3 | M4 | M5 |
|-------|------:|------:|------:|------:|------:|
| DeepSeek R1 Distill 14B | - | - | - | - | 5.6 |
| DeepSeek R1 Distill 32B | - | - | - | - | 2.6 |
| DeepSeek R1 Distill 7B | - | - | - | - | 11.4 |
| DeepSeek-R1-Distill-Qwen-14B-4bit | - | - | - | - | 10.8 |
| DeepSeek-R1-Distill-Qwen-32B-MLX-4Bit | - | - | - | - | 4.8 |
| DeepSeek-R1-Distill-Qwen-7B-4bit-mlx | - | - | - | - | 26.2 |
| Devstral Small 24B | - | - | - | - | 3.5 |
| Devstral-Small-2-24B-Instruct-2512-4bit | - | - | - | - | 6.6 |
| Gemma 3 12B | - | - | - | - | 5.7 |
| Gemma 3 1B | - | - | - | - | 46.6 |
| Gemma 3 27B | - | - | - | - | 3.0 |
| Gemma 3 4B | - | - | - | - | 16.5 |
| Gemma 4 26B-A4B MoE | - | - | - | - | 16.2 |
| Gemma 4 31B | - | - | - | - | 5.5 |
| Gemma 4 E2B | - | - | - | - | 29.2 |
| Gemma 4 E4B | - | - | - | - | 36.7 |
| Llama 3.1 8B Instruct | - | - | - | - | 10.8 |
| Llama 3.2 1B Instruct | - | - | - | - | 59.4 |
| Llama 3.2 3B Instruct | - | - | - | - | 24.1 |
| Llama-3.2-1B-Instruct-4bit | - | - | - | - | 156.7 |
| Llama-3.2-3B-Instruct-4bit | - | - | - | - | 63.1 |
| Meta-Llama-3.1-8B-Instruct-4bit | - | - | - | - | 28.3 |
| Mistral 7B Instruct v0.3 | - | - | - | - | 11.5 |
| Mistral Nemo 12B | - | - | - | - | 6.9 |
| Mistral Small 3.1 24B | - | - | - | - | 3.6 |
| Mistral-7B-Instruct-v0.3-4bit | - | - | - | - | 22.9 |
| Mistral-Nemo-Instruct-2407-4bit | - | - | - | - | 13.4 |
| Mistral-Small-3.1-Text-24B-Instruct-2503-4bit | - | - | - | - | 6.9 |
| Phi 4 14B | - | - | - | - | 5.3 |
| Phi 4 Mini 3.8B | - | - | - | - | 19.6 |
| Phi 4 Mini Reasoning 3.8B | - | - | - | - | 19.4 |
| Phi 4 Reasoning Plus 14B | - | - | - | - | 5.7 |
| Phi-4-mini-instruct-4bit | - | - | - | - | 52.0 |
| QwQ 32B | - | - | - | - | 2.6 |
| QwQ-32B-4bit | - | - | - | - | 4.4 |
| Qwen 2.5 Coder 14B | - | - | - | - | 5.9 |
| Qwen 2.5 Coder 32B | - | - | - | - | 2.5 |
| Qwen 2.5 Coder 7B | - | - | - | - | 11.3 |
| Qwen 3 0.6B | - | - | - | - | 91.9 |
| Qwen 3 1.7B | - | - | - | - | 37.3 |
| Qwen 3 14B | - | - | - | - | 5.8 |
| Qwen 3 30B-A3B MoE | - | - | - | - | 23.1 |
| Qwen 3 32B | - | - | - | - | 2.5 |
| Qwen 3 4B | - | - | - | - | 16.5 |
| Qwen 3 8B | - | - | - | - | 9.1 |
| Qwen 3.5 27B | - | - | - | - | 4.4 |
| Qwen 3.5 35B-A3B MoE | - | - | - | - | 31.3 |
| Qwen 3.5 4B | - | - | - | - | 29.4 |
| Qwen 3.5 9B | - | - | - | - | 13.2 |
| Qwen2.5-Coder-14B-Instruct-4bit | - | - | - | - | 10.9 |
| Qwen2.5-Coder-32B-Instruct-4bit | - | - | - | - | 4.8 |
| Qwen2.5-Coder-7B-Instruct-4bit | - | - | - | - | 23.5 |
| Qwen3-0.6B-4bit | - | - | - | - | 259.1 |
| Qwen3-8B-4bit | - | - | - | - | 24.0 |
| Qwen3.5-35B-A3B-4bit | - | - | - | - | 58.8 |
| Qwen3.5-4B-4bit | - | - | - | - | 48.7 |
| Qwen3.5-9B-MLX-4bit | - | - | - | - | 21.5 |
| gemma-3-12b-it-4bit | - | - | - | - | 12.5 |
| gemma-3-1b-it-4bit | - | - | - | - | 176.7 |
| gemma-3-27b-it-4bit | - | - | - | - | 5.5 |
| gemma-3-4b-it-4bit | - | - | - | - | 53.3 |
| phi-4-4bit | - | - | - | - | 11.6 |

*Best tg128 across all variants within each generation.*

---

*Auto-generated — run `python3 scripts/generate_results.py` to regenerate.*