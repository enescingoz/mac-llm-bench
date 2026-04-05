#!/usr/bin/env bash
# detect_hardware.sh — Detect Mac hardware specifications
# Outputs hardware info as shell variables or JSON

set -euo pipefail

detect_hardware() {
    # Chip name (e.g., "Apple M5")
    CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")

    # Total RAM in GB
    TOTAL_RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
    TOTAL_RAM_GB=$(( TOTAL_RAM_BYTES / 1073741824 ))

    # Available RAM in GB (approximate)
    AVAILABLE_RAM_PAGES=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
    INACTIVE_PAGES=$(vm_stat 2>/dev/null | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')
    PAGE_SIZE=$(sysctl -n hw.pagesize 2>/dev/null || echo "16384")
    AVAILABLE_RAM_GB=$(echo "scale=1; (${AVAILABLE_RAM_PAGES:-0} + ${INACTIVE_PAGES:-0}) * $PAGE_SIZE / 1073741824" | bc 2>/dev/null || echo "0")

    # CPU cores
    CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "0")
    PERF_CORES=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo "0")
    EFF_CORES=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo "0")

    # GPU cores — parse from system_profiler
    GPU_CORES=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Total Number of Cores/ {print $2; exit}' || echo "0")
    if [[ -z "$GPU_CORES" || "$GPU_CORES" == "0" ]]; then
        # Fallback: try to get from Metal
        GPU_CORES=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Cores/ {print $2; exit}' || echo "unknown")
    fi

    # Mac model
    MAC_MODEL=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
    MAC_MODEL_NAME=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ {print $2; exit}' || echo "Unknown")
    MAC_CHIP_NAME=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip/ {print $2; exit}' || echo "$CHIP")

    # OS version
    OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")

    # Power source
    POWER_SOURCE="unknown"
    if command -v pmset &>/dev/null; then
        if pmset -g ps 2>/dev/null | grep -q "AC Power"; then
            POWER_SOURCE="ac_power"
        else
            POWER_SOURCE="battery"
        fi
    fi

    # Available disk space in GB
    DISK_AVAILABLE_GB=$(df -g / 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
}

# Output as shell variables (sourceable)
output_shell() {
    detect_hardware
    echo "HW_MAC_MODEL=\"$MAC_MODEL_NAME\""
    echo "HW_CHIP=\"$MAC_CHIP_NAME\""
    echo "HW_TOTAL_RAM_GB=$TOTAL_RAM_GB"
    echo "HW_AVAILABLE_RAM_GB=$AVAILABLE_RAM_GB"
    echo "HW_CPU_CORES=$CPU_CORES"
    echo "HW_PERF_CORES=$PERF_CORES"
    echo "HW_EFF_CORES=$EFF_CORES"
    echo "HW_GPU_CORES=$GPU_CORES"
    echo "HW_OS_VERSION=\"$OS_VERSION\""
    echo "HW_POWER_SOURCE=\"$POWER_SOURCE\""
    echo "HW_DISK_AVAILABLE_GB=$DISK_AVAILABLE_GB"
}

# Output as JSON
output_json() {
    detect_hardware
    cat <<ENDJSON
{
  "model": "$MAC_MODEL_NAME",
  "chip": "$MAC_CHIP_NAME",
  "total_ram_gb": $TOTAL_RAM_GB,
  "available_ram_gb": $AVAILABLE_RAM_GB,
  "cpu_cores": $CPU_CORES,
  "performance_cores": $PERF_CORES,
  "efficiency_cores": $EFF_CORES,
  "gpu_cores": "$GPU_CORES",
  "os_version": "$OS_VERSION",
  "power_source": "$POWER_SOURCE",
  "disk_available_gb": $DISK_AVAILABLE_GB
}
ENDJSON
}

# Print human-readable summary
output_summary() {
    detect_hardware
    echo "═══════════════════════════════════════════════════"
    echo "  Hardware Detection"
    echo "═══════════════════════════════════════════════════"
    echo "  Machine:      $MAC_MODEL_NAME"
    echo "  Chip:         $MAC_CHIP_NAME"
    echo "  RAM:          ${TOTAL_RAM_GB} GB total, ~${AVAILABLE_RAM_GB} GB available"
    echo "  CPU Cores:    $CPU_CORES ($PERF_CORES performance + $EFF_CORES efficiency)"
    echo "  GPU Cores:    $GPU_CORES"
    echo "  macOS:        $OS_VERSION"
    echo "  Power:        $POWER_SOURCE"
    echo "  Disk Free:    ${DISK_AVAILABLE_GB} GB"
    echo "═══════════════════════════════════════════════════"
}

# Main: accept --json, --shell, or --summary (default)
case "${1:-}" in
    --json)    output_json ;;
    --shell)   output_shell ;;
    --summary) output_summary ;;
    *)         output_summary ;;
esac
