# Benchmark Results

Community-contributed benchmark results for LLMs on Apple Silicon.

Browse by chip generation, then select your variant (base, Pro, Max, Ultra).

| Generation | Variants with Data | Total Configs | Total Models | Link |
|------------|--------------------|---------------|--------------|------|
| **M1** | - | - | - | [Awaiting contributions](m1/) |
| **M2** | - | - | - | [Awaiting contributions](m2/) |
| **M3** | - | - | - | [Awaiting contributions](m3/) |
| **M4** | - | - | - | [Awaiting contributions](m4/) |
| **M5** | 1 | 1 | 37 | [View results](m5/) |

## Quick Comparison

Best `tg128` (text generation, tok/s) per generation:

| Model | M1 | M2 | M3 | M4 | M5 |
|-------|------:|------:|------:|------:|------:|
| DeepSeek R1 Distill 14B | - | - | - | - | 5.6 |
| DeepSeek R1 Distill 32B | - | - | - | - | 2.6 |
| DeepSeek R1 Distill 7B | - | - | - | - | 11.4 |
| Devstral Small 24B | - | - | - | - | 3.5 |
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
| Mistral 7B Instruct v0.3 | - | - | - | - | 11.5 |
| Mistral Nemo 12B | - | - | - | - | 6.9 |
| Mistral Small 3.1 24B | - | - | - | - | 3.6 |
| Phi 4 14B | - | - | - | - | 5.3 |
| Phi 4 Mini 3.8B | - | - | - | - | 19.6 |
| Phi 4 Mini Reasoning 3.8B | - | - | - | - | 19.4 |
| Phi 4 Reasoning Plus 14B | - | - | - | - | 5.7 |
| QwQ 32B | - | - | - | - | 2.6 |
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

*Best tg128 across all variants within each generation.*

---

*Auto-generated — run `python3 scripts/generate_results.py` to regenerate.*