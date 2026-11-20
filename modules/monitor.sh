#!/usr/bin/env bash
# ==============================================================================
# File: modules/monitor.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: System Telemetry Monitor. Gathers and visualizes real-time metrics
#          for CPU, RAM, Swap, Disks, Battery, and Temperature directly
#          from Linux kernel interfaces (/proc and /sys).
# ==============================================================================

# ==============================================================================
# Quick Metric Gatherers (Optimized for instantaneous Dashboard display)
# ==============================================================================

# Quick CPU Usage calculation using delta between two rapid reads
# OS Concept: /proc/stat exposes kernel jiffies (ticks) spent in user, nice, system, idle, iowait...
get_quick_cpu() {
    local s1 s2
    s1="$(grep '^cpu ' /proc/stat 2>/dev/null || echo "")"
    # Brief 0.15s sleep for instantaneous menu render responsiveness
    sleep 0.15
    s2="$(grep '^cpu ' /proc/stat 2>/dev/null || echo "")"

    if [[ -z "${s1}" || -z "${s2}" ]]; then
        echo "0.0"
        return
    fi

    awk -v s1="${s1}" -v s2="${s2}" 'BEGIN {
        split(s1, a1);
        split(s2, a2);
        idle1 = a1[5] + a1[6];
        idle2 = a2[5] + a2[6];
        tot1 = 0; tot2 = 0;
        for (i = 2; i <= 11; i++) {
            tot1 += a1[i];
            tot2 += a2[i];
        }
        didle = idle2 - idle1;
        dtot = tot2 - tot1;
        if (dtot <= 0) {
            printf "0.0";
        } else {
            usage = (1.0 - (didle / dtot)) * 100.0;
            if (usage < 0.0) usage = 0.0;
            if (usage > 100.0) usage = 100.0;
            printf "%.1f", usage;
        }
    }'
}

# RAM Usage Percentage from /proc/meminfo
# OS Concept: MemAvailable represents memory that can be allocated without swapping.
get_quick_ram() {
    awk '
    /^MemTotal:/ { total = $2 }
    /^MemFree:/ { free = $2 }
    /^MemAvailable:/ { avail = $2 }
    END {
        if (avail == 0) avail = free;
        used = total - avail;
        if (total > 0) {
            printf "%.1f", (used / total) * 100.0;
        } else {
            printf "0.0";
        }
    }' /proc/meminfo 2>/dev/null || echo "0.0"
}

# Root Partition Disk Usage Percentage
# OS Concept: VFS superblock queries via statvfs / df
get_quick_disk() {
    df -k / 2>/dev/null | tail -n 1 | awk '{ gsub("%", "", $(NF-1)); print $(NF-1) }' || echo "0"
}

# Battery capacity and state from sysfs
# OS Concept: ACPI / sysfs power_supply class device interface
get_quick_battery() {
    local bat_cap=""
    local bat_stat=""

    for bat in /sys/class/power_supply/BAT*; do
        if [[ -r "${bat}/capacity" ]]; then
            bat_cap="$(cat "${bat}/capacity" 2>/dev/null)"
            bat_stat="$(cat "${bat}/status" 2>/dev/null)"
            printf "%s%% (%s)" "${bat_cap}" "${bat_stat:-Unknown}"
            return
        fi
    done
    echo "N/A"
}

# System uptime from /proc/uptime
# OS Concept: Kernel uptime timer jiffies converted into elapsed human time
get_quick_uptime() {
    if [[ -r /proc/uptime ]]; then
        awk '{
            sec = int($1);
            days = int(sec / 86400);
            hrs = int((sec % 86400) / 3600);
            mins = int((sec % 3600) / 60);
            if (days > 0) {
                printf "%dd %dh %dm", days, hrs, mins;
            } else {
                printf "%dh %dm", hrs, mins;
            }
        }' /proc/uptime
    else
        uptime -p 2>/dev/null || echo "N/A"
    fi
}

# 1-minute load average from /proc/loadavg
# OS Concept: Number of jobs in the kernel run queue or waiting for disk I/O
get_quick_load() {
    if [[ -r /proc/loadavg ]]; then
        awk '{ print $1 }' /proc/loadavg
    else
        echo "0.00"
    fi
}

# Total process count
# OS Concept: Counting tasks currently tracked in kernel task_struct table
get_total_processes_count() {
    if has_cmd ps; then
        ps -e --no-headers 2>/dev/null | wc -l | tr -d ' '
    else
        find /proc -maxdepth 1 -name '[0-9]*' 2>/dev/null | wc -l | tr -d ' '
    fi
}

# ==============================================================================
# Full Detailed Metric Functions
# ==============================================================================

# Precise 1-Second CPU Usage Calculation
# ------------------------------------------------------------------------------
# Mathematical Formula:
#   idle  = idle_ticks + iowait_ticks
#   total = sum(user + nice + system + idle + iowait + irq + softirq + steal)
#   Δidle = idle_reading_2 - idle_reading_1
#   Δtotal = total_reading_2 - total_reading_1
#   CPU_Usage_% = (1 - (Δidle / Δtotal)) * 100
# ------------------------------------------------------------------------------
calculate_detailed_cpu() {
    local stat_first
    local stat_second

    stat_first="$(grep '^cpu ' /proc/stat 2>/dev/null)"
    sleep 1
    stat_second="$(grep '^cpu ' /proc/stat 2>/dev/null)"

    awk -v s1="${stat_first}" -v s2="${stat_second}" 'BEGIN {
        split(s1, a1);
        split(s2, a2);

        # idle ticks = field 5 (idle) + field 6 (iowait)
        idle1 = a1[5] + a1[6];
        idle2 = a2[5] + a2[6];

        # Total ticks = fields 2 through 11
        tot1 = 0; tot2 = 0;
        for (i = 2; i <= 11; i++) {
            tot1 += a1[i];
            tot2 += a2[i];
        }

        diff_idle = idle2 - idle1;
        diff_total = tot2 - tot1;

        if (diff_total <= 0) {
            printf "0.0";
        } else {
            usage = (1.0 - (diff_idle / diff_total)) * 100.0;
            if (usage < 0.0) usage = 0.0;
            if (usage > 100.0) usage = 100.0;
            printf "%.1f", usage;
        }
    }'
}

# Comprehensive RAM and Swap metrics
# Reads /proc/meminfo and returns formatted table data
get_ram_details() {
    awk '
    /^MemTotal:/     { total = $2 }
    /^MemFree:/      { free = $2 }
    /^MemAvailable:/ { avail = $2 }
    /^Buffers:/      { buffers = $2 }
    /^Cached:/       { cached = $2 }
    /^SwapTotal:/    { swap_total = $2 }
    /^SwapFree:/     { swap_free = $2 }
    END {
        if (avail == 0) avail = free + buffers + cached;
        used = total - avail;
        pct = (total > 0) ? (used / total) * 100.0 : 0.0;
        
        swap_used = swap_total - swap_free;
        swap_pct = (swap_total > 0) ? (swap_used / swap_total) * 100.0 : 0.0;

        printf "RAM_USED_PCT=%.1f\n", pct
        printf "RAM_TOTAL_MB=%d\n", total / 1024
        printf "RAM_USED_MB=%d\n", used / 1024
        printf "RAM_AVAIL_MB=%d\n", avail / 1024
        printf "RAM_FREE_MB=%d\n", free / 1024
        printf "RAM_BUFFERS_MB=%d\n", buffers / 1024
        printf "RAM_CACHED_MB=%d\n", cached / 1024
        printf "SWAP_TOTAL_MB=%d\n", swap_total / 1024
        printf "SWAP_USED_MB=%d\n", swap_used / 1024
        printf "SWAP_FREE_MB=%d\n", swap_free / 1024
        printf "SWAP_USED_PCT=%.1f\n", swap_pct
    }' /proc/meminfo 2>/dev/null
}

# CPU Temperature in Celsius
# OS Concept: sysfs thermal class hardware sensor monitoring
get_cpu_temperature() {
    local temp_raw=""
    for zone in /sys/class/thermal/thermal_zone*; do
        if [[ -r "${zone}/temp" ]]; then
            temp_raw="$(cat "${zone}/temp" 2>/dev/null)"
            if [[ -n "${temp_raw}" && "${temp_raw}" -gt 0 ]]; then
                awk -v t="${temp_raw}" 'BEGIN { printf "%.1f°C", t / 1000.0 }'
                return
            fi
        fi
    done
    echo "N/A"
}

# Static System Details: CPU Model, Core count, Architecture, Kernel
get_system_specs() {
    local cpu_model
    local core_count
    local kernel_ver
    local arch

    cpu_model="$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed -e 's/^[[:space:]]*//')"
    [[ -z "${cpu_model}" ]] && cpu_model="$(lscpu 2>/dev/null | grep 'Model name:' | cut -d: -f2- | sed -e 's/^[[:space:]]*//')"
    [[ -z "${cpu_model}" ]] && cpu_model="Generic x86/ARM Processor"

    core_count="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "1")"
    kernel_ver="$(uname -r 2>/dev/null || echo "Unknown")"
    arch="$(uname -m 2>/dev/null || echo "Unknown")"

    printf "CPU Model    : %s\n" "${cpu_model}"
    printf "CPU Cores    : %s core(s) [%s]\n" "${core_count}" "${arch}"
    printf "Kernel Ver   : %s\n" "${kernel_ver}"
}

# ==============================================================================
# Live System Monitor Interface
# ==============================================================================
menu_system_monitor() {
    log_action "Viewed Live System Monitor"
    local refresh_sec="${REFRESH_INTERVAL:-3}"
    local key_pressed=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                         NEXADMIN - LIVE SYSTEM MONITOR                         %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        
        # 1. Hardware & System Specs
        printf "%s[SYSTEM IDENTIFICATION]%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
        get_system_specs
        printf "System Uptime: %s\n" "$(get_quick_uptime)"
        printf "Load Averages: %s (1m, 5m, 15m)\n\n" "$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')"

        # 2. CPU Usage & Temp
        printf "%s[CPU TELEMETRY]%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
        local cpu_pct
        cpu_pct="$(get_quick_cpu)"
        printf "CPU Utilization : "
        progress_bar "${cpu_pct}" 30
        printf "\n"
        printf "CPU Temperature : %s\n\n" "$(get_cpu_temperature)"

        # 3. RAM & Swap Utilization
        printf "%s[MEMORY & SWAP TELEMETRY]%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
        local ram_info
        ram_info="$(get_ram_details)"
        local ram_pct used_mb total_mb avail_mb swap_pct swap_used swap_tot
        ram_pct="$(echo "${ram_info}" | grep 'RAM_USED_PCT=' | cut -d= -f2)"
        used_mb="$(echo "${ram_info}" | grep 'RAM_USED_MB=' | cut -d= -f2)"
        total_mb="$(echo "${ram_info}" | grep 'RAM_TOTAL_MB=' | cut -d= -f2)"
        avail_mb="$(echo "${ram_info}" | grep 'RAM_AVAIL_MB=' | cut -d= -f2)"
        swap_pct="$(echo "${ram_info}" | grep 'SWAP_USED_PCT=' | cut -d= -f2)"
        swap_used="$(echo "${ram_info}" | grep 'SWAP_USED_MB=' | cut -d= -f2)"
        swap_tot="$(echo "${ram_info}" | grep 'SWAP_TOTAL_MB=' | cut -d= -f2)"

        printf "Physical RAM    : "
        progress_bar "${ram_pct}" 30
        printf "  (%s MB used / %s MB total, %s MB available)\n" "${used_mb}" "${total_mb}" "${avail_mb}"

        printf "Swap Space      : "
        progress_bar "${swap_pct}" 30
        printf "  (%s MB used / %s MB total)\n\n" "${swap_used}" "${swap_tot}"

        # 4. Battery Telemetry
        printf "%s[POWER & BATTERY STATUS]%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
        printf "Battery Status  : %s\n\n" "$(get_quick_battery)"

        # 5. Mounted Partition Storage
        printf "%s[MOUNTED STORAGE VOLUMES]%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
        printf "%-20s %-10s %-10s %-10s %-8s %-20s\n" "Filesystem" "Size" "Used" "Avail" "Use%" "Mounted On"
        printf "%s\n" "--------------------------------------------------------------------------------"
        df -h 2>/dev/null | grep -E '^/dev/' | grep -v '/snap/' | while read -r fs size used avail pcent mnt; do
            printf "%-20s %-10s %-10s %-10s %-8s %-20s\n" "${fs}" "${size}" "${used}" "${avail}" "${pcent}" "${mnt}"
        done
        printf "\n%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Auto-refreshing every %s seconds. Press %s'q'%s to return to main menu.\n" \
            "${refresh_sec}" "${COLOR_YELLOW}" "${COLOR_RESET}"

        # Non-blocking key read with timeout
        read -r -t "${refresh_sec}" -n 1 key_pressed || true
        if [[ "${key_pressed}" == "q" || "${key_pressed}" == "Q" ]]; then
            break
        fi
    done
}
