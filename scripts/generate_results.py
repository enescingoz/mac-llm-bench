#!/usr/bin/env python3
"""Generate results README.md files from raw JSON benchmark data.

Structure:
  results/
    README.md                         — Overview index
    {generation}/
      README.md                       — Generation overview with links to variants
      {variant}/
        README.md                     — Benchmark tables (or awaiting contributions)
        raw/{chip}_{cpu}c-{gpu}g_{ram}gb/*.json

Run: python3 scripts/generate_results.py
"""

import json
import os
import glob
from collections import defaultdict

RESULTS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "results")

GENERATIONS = ["m1", "m2", "m3", "m4", "m5"]
VARIANTS = ["base", "pro", "max", "ultra"]

CONTRIB_LINK = "[CONTRIBUTING.md](../../CONTRIBUTING.md)"
GUIDE_LINK = "[GUIDE.md](../../GUIDE.md)"


def parse_chip_folder(folder_name):
    """Parse 'm5_10c-10g_32gb' or 'm4-pro_14c-20g_48gb'."""
    parts = folder_name.split("_")
    if len(parts) < 3:
        return None

    chip = parts[0]
    if "-" in chip:
        generation, variant = chip.split("-", 1)
    else:
        generation = chip
        variant = "base"

    cores = parts[1]
    cpu_cores = cores.split("c-")[0] if "c-" in cores else "?"
    gpu_cores = cores.split("-")[1].replace("g", "") if "-" in cores else "?"

    ram = parts[2].replace("gb", "")

    return {
        "generation": generation,
        "variant": variant,
        "cpu_cores": int(cpu_cores) if cpu_cores != "?" else 0,
        "gpu_cores": int(gpu_cores) if gpu_cores != "?" else 0,
        "ram_gb": int(ram) if ram.isdigit() else 0,
        "folder": folder_name,
    }


def load_all_results():
    """Load all results: {generation: {variant: {config_folder: [results]}}}"""
    data = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))

    for gen in GENERATIONS:
        for variant in VARIANTS:
            raw_dir = os.path.join(RESULTS_DIR, gen, variant, "raw")
            if not os.path.isdir(raw_dir):
                continue

            for chip_dir in sorted(glob.glob(os.path.join(raw_dir, "*"))):
                if not os.path.isdir(chip_dir):
                    continue
                folder_name = os.path.basename(chip_dir)

                for json_file in sorted(glob.glob(os.path.join(chip_dir, "*.json"))):
                    try:
                        with open(json_file) as f:
                            result = json.load(f)
                        data[gen][variant][folder_name].append(result)
                    except (json.JSONDecodeError, IOError):
                        continue

    return data


def chip_display_name(folder_name):
    """'m5_10c-10g_32gb' -> 'M5 - 10 CPU / 10 GPU / 32GB'"""
    info = parse_chip_folder(folder_name)
    if not info:
        return folder_name
    gen = info["generation"].upper()
    variant = info["variant"]
    if variant != "base":
        gen = f"{gen} {variant.capitalize()}"
    return f"{gen} - {info['cpu_cores']} CPU / {info['gpu_cores']} GPU / {info['ram_gb']}GB"


def variant_display(gen, variant):
    """'m5', 'pro' -> 'M5 Pro'"""
    gen_upper = gen.upper()
    if variant == "base":
        return gen_upper
    return f"{gen_upper} {variant.capitalize()}"


def render_results_table(results):
    """Render a markdown benchmark table from a list of result dicts."""
    lines = []
    lines.append("| Model | Quant | pp128 | pp256 | pp512 | tg128 | tg256 | Memory |")
    lines.append("|-------|-------|------:|------:|------:|------:|------:|-------:|")

    results.sort(key=lambda r: r.get("speed", {}).get("tg128", 0), reverse=True)

    for r in results:
        m = r.get("model", {})
        s = r.get("speed", {})
        mem = r.get("memory", {})

        name = m.get("name", "?")
        quant = m.get("quant", "?")
        pp128 = f"{s['pp128']:.1f}" if "pp128" in s else "-"
        pp256 = f"{s['pp256']:.1f}" if "pp256" in s else "-"
        pp512 = f"{s['pp512']:.1f}" if "pp512" in s else "-"
        tg128 = f"{s['tg128']:.1f}" if "tg128" in s else "-"
        tg256 = f"{s['tg256']:.1f}" if "tg256" in s else "-"
        peak_mem = f"{mem['peak_rss_gb']:.2f}" if "peak_rss_gb" in mem else "-"

        lines.append(
            f"| {name} | {quant} | {pp128} | {pp256} | {pp512} | {tg128} | {tg256} | {peak_mem} |"
        )

    return "\n".join(lines)


# ─── Variant README (e.g., results/m5/base/README.md) ─────────────
def generate_variant_readme(gen, variant, configs):
    """Generate README for a single variant folder."""
    display = variant_display(gen, variant)
    lines = []
    lines.append(f"# {display} Benchmarks\n")

    if not configs:
        lines.append("No benchmark results yet for this chip variant.\n")
        lines.append(f"**Your contribution is welcome!** Run the benchmarks on your {display} and submit the results.\n")
        lines.append(f"See {GUIDE_LINK} for how to run benchmarks and {CONTRIB_LINK} for how to submit results.\n")
        return "\n".join(lines)

    lines.append("All speed values are in **tokens/second** from `llama-bench` (higher = better). Memory is peak RSS in GB.\n")

    # Each config (different CPU/GPU/RAM combo) gets its own section
    for folder_name in sorted(configs.keys()):
        results = configs[folder_name]
        if not results:
            continue

        config_display = chip_display_name(folder_name)
        lines.append(f"## {config_display}\n")
        lines.append(render_results_table(results))
        lines.append("")

    lines.append("---\n")
    lines.append(
        f"*Auto-generated from raw benchmark data in [`raw/`](raw/). "
        f"Run `python3 scripts/generate_results.py` to regenerate.*"
    )

    return "\n".join(lines)


# ─── Generation README (e.g., results/m5/README.md) ───────────────
def generate_generation_readme(gen, variants_data):
    """Generate README for a generation folder — overview with links to variants."""
    gen_upper = gen.upper()
    lines = []
    lines.append(f"# Apple {gen_upper} Benchmarks\n")
    lines.append(f"Select your {gen_upper} chip variant:\n")

    lines.append("| Variant | Configurations | Models Tested | Status |")
    lines.append("|---------|----------------|---------------|--------|")

    for variant in VARIANTS:
        display = variant_display(gen, variant)
        configs = variants_data.get(variant, {})

        total_results = sum(len(r) for r in configs.values())
        total_configs = sum(1 for r in configs.values() if r)
        model_names = set()
        for results in configs.values():
            for r in results:
                model_names.add(r.get("model", {}).get("name", "?"))

        if total_results > 0:
            status = f"{total_configs} config(s), {len(model_names)} model(s)"
            lines.append(f"| [{display}]({variant}/) | {total_configs} | {len(model_names)} | {status} |")
        else:
            lines.append(f"| [{display}]({variant}/) | - | - | Awaiting contributions |")

    lines.append(f"\nSee {CONTRIB_LINK} for how to add your results.\n")

    lines.append("---\n")
    lines.append("*Auto-generated — run `python3 scripts/generate_results.py` to regenerate.*")

    return "\n".join(lines)


# ─── Top-level index (results/README.md) ──────────────────────────
def generate_index_readme(all_data):
    """Generate the main results/README.md index."""
    lines = []
    lines.append("# Benchmark Results\n")
    lines.append("Community-contributed benchmark results for LLMs on Apple Silicon.\n")
    lines.append("Browse by chip generation, then select your variant (base, Pro, Max, Ultra).\n")

    lines.append("| Generation | Variants with Data | Total Configs | Total Models | Link |")
    lines.append("|------------|--------------------|---------------|--------------|------|")

    for gen in GENERATIONS:
        gen_upper = gen.upper()
        variants_data = all_data.get(gen, {})

        variants_with_data = 0
        total_configs = 0
        model_names = set()

        for variant in VARIANTS:
            configs = variants_data.get(variant, {})
            has_data = any(len(r) > 0 for r in configs.values())
            if has_data:
                variants_with_data += 1
                total_configs += sum(1 for r in configs.values() if r)
                for results in configs.values():
                    for r in results:
                        model_names.add(r.get("model", {}).get("name", "?"))

        if variants_with_data > 0:
            lines.append(
                f"| **{gen_upper}** | {variants_with_data} | {total_configs} | {len(model_names)} | "
                f"[View results]({gen}/) |"
            )
        else:
            lines.append(f"| **{gen_upper}** | - | - | - | [Awaiting contributions]({gen}/) |")

    # Quick comparison table
    all_model_names = set()
    for gen_data in all_data.values():
        for variant_data in gen_data.values():
            for results in variant_data.values():
                for r in results:
                    all_model_names.add(r.get("model", {}).get("name", "?"))

    if all_model_names:
        lines.append("\n## Quick Comparison\n")
        lines.append("Best `tg128` (text generation, tok/s) per generation:\n")

        header = "| Model |"
        sep = "|-------|"
        for gen in GENERATIONS:
            header += f" {gen.upper()} |"
            sep += "------:|"
        lines.append(header)
        lines.append(sep)

        for model_name in sorted(all_model_names):
            row = f"| {model_name} |"
            for gen in GENERATIONS:
                best = 0
                for variant_data in all_data.get(gen, {}).values():
                    for results in variant_data.values():
                        for r in results:
                            if r.get("model", {}).get("name") == model_name:
                                tg128 = r.get("speed", {}).get("tg128", 0)
                                if tg128 > best:
                                    best = tg128
                row += f" {best:.1f} |" if best > 0 else " - |"
            lines.append(row)

        lines.append("\n*Best tg128 across all variants within each generation.*\n")

    lines.append("---\n")
    lines.append("*Auto-generated — run `python3 scripts/generate_results.py` to regenerate.*")

    return "\n".join(lines)


# ─── Main ─────────────────────────────────────────────────────────
def main():
    print("Loading results...")
    all_data = load_all_results()

    total = sum(
        len(results)
        for gen_data in all_data.values()
        for variant_data in gen_data.values()
        for results in variant_data.values()
    )
    print(f"Found {total} benchmark result(s)")

    # Ensure all generation/variant folders exist
    for gen in GENERATIONS:
        for variant in VARIANTS:
            os.makedirs(os.path.join(RESULTS_DIR, gen, variant, "raw"), exist_ok=True)

    # Generate variant READMEs (the leaf level — actual tables or "awaiting")
    for gen in GENERATIONS:
        for variant in VARIANTS:
            configs = all_data.get(gen, {}).get(variant, {})
            readme_path = os.path.join(RESULTS_DIR, gen, variant, "README.md")
            content = generate_variant_readme(gen, variant, configs)
            with open(readme_path, "w") as f:
                f.write(content)
            status = f"{sum(len(r) for r in configs.values())} results" if configs else "awaiting"
            print(f"  {gen}/{variant}/README.md ({status})")

    # Generate generation READMEs (overview with links to variants)
    for gen in GENERATIONS:
        variants_data = all_data.get(gen, {})
        readme_path = os.path.join(RESULTS_DIR, gen, "README.md")
        content = generate_generation_readme(gen, variants_data)
        with open(readme_path, "w") as f:
            f.write(content)
        print(f"  {gen}/README.md")

    # Generate top-level index
    index_path = os.path.join(RESULTS_DIR, "README.md")
    content = generate_index_readme(all_data)
    with open(index_path, "w") as f:
        f.write(content)
    print(f"  README.md")

    print("Done!")


if __name__ == "__main__":
    main()
