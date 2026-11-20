#!/usr/bin/env bash
# ==============================================================================
# File: modules/report.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: Historical Telemetry & Health Reporting Engine. Logs time-series
#          system metrics to CSV, renders ASCII text bar charts, and compiles
#          comprehensive system health audit reports.
# ==============================================================================

HISTORY_CSV="${BASE_DIR}/data/history.csv"
RECORDER_PID_FILE="${BASE_DIR}/data/.history_recorder.pid"
REPORTS_DIR="${BASE_DIR}/reports"

mkdir -p "${REPORTS_DIR}"

# Initializes CSV header if file is missing or empty
init_history_csv() {
    if [[ ! -f "${HISTORY_CSV}" || ! -s "${HISTORY_CSV}" ]]; then
        echo "Timestamp,CPU_Percent,RAM_Percent,Disk_Percent,Active_Processes" > "${HISTORY_CSV}"
    fi
}

# ==============================================================================
# 1. Record Single Historical Snapshot
# OS Concept: Periodic time-series system metric collection for capacity planning
# ==============================================================================
record_history_snapshot() {
    init_history_csv

    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local cpu_val ram_val disk_val proc_cnt
    cpu_val="$(get_quick_cpu)"
    ram_val="$(get_quick_ram)"
    disk_val="$(get_quick_disk)"
    proc_cnt="$(get_total_processes_count)"

    printf "%s,%s,%s,%s,%s\n" "${timestamp}" "${cpu_val}" "${ram_val}" "${disk_val}" "${proc_cnt}" >> "${HISTORY_CSV}"
    log_action "Recorded telemetry snapshot: CPU=${cpu_val}%, RAM=${ram_val}%, Disk=${disk_val}%, Procs=${proc_cnt}"
}

# ==============================================================================
# 2. Background Time-Series Recording Daemon
# OS Concept: Background telemetry ingestion service
# ==============================================================================
is_history_recorder_running() {
    if [[ -f "${RECORDER_PID_FILE}" ]]; then
        local pid
        pid="$(cat "${RECORDER_PID_FILE}" 2>/dev/null)"
        if is_number "${pid}" && is_pid "${pid}"; then
            return 0
        fi
    fi
    return 1
}

start_history_recorder() {
    if is_history_recorder_running; then
        local existing_pid
        existing_pid="$(cat "${RECORDER_PID_FILE}")"
        printf "%s[NOTICE] History recorder daemon is already running (PID: %s).%s\n" "${COLOR_YELLOW}" "${existing_pid}" "${COLOR_RESET}"
        return 0
    fi

    local interval="${HISTORY_RECORD_INTERVAL:-30}"

    (
        while true; do
            record_history_snapshot
            sleep "${interval}"
        done
    ) >/dev/null 2>&1 &

    local r_pid=$!
    echo "${r_pid}" > "${RECORDER_PID_FILE}"
    log_action "Started background history recorder (PID: ${r_pid}, interval: ${interval}s)"
    printf "%s[SUCCESS] History recorder daemon started (PID: %s, logging every %ss).%s\n" \
        "${COLOR_GREEN}" "${r_pid}" "${interval}" "${COLOR_RESET}"
}

stop_history_recorder() {
    if ! is_history_recorder_running; then
        printf "%s[NOTICE] History recorder daemon is not currently active.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        rm -f "${RECORDER_PID_FILE}" 2>/dev/null || true
        return 0
    fi

    local r_pid
    r_pid="$(cat "${RECORDER_PID_FILE}" 2>/dev/null)"

    if is_number "${r_pid}" && is_pid "${r_pid}"; then
        kill -15 "${r_pid}" 2>/dev/null || kill -9 "${r_pid}" 2>/dev/null || true
        log_action "Stopped history recorder daemon (PID: ${r_pid})"
        printf "%s[SUCCESS] History recorder daemon (PID: %s) stopped.%s\n" "${COLOR_GREEN}" "${r_pid}" "${COLOR_RESET}"
    fi

    rm -f "${RECORDER_PID_FILE}" 2>/dev/null || true
}

# ==============================================================================
# 3. View Historical Telemetry Table & ASCII Bar Chart
# OS Concept: Visual representation of time-series resource consumption
# ==============================================================================
view_history_table_and_graph() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                  HISTORICAL TELEMETRY (LAST 20 LOGGED SAMPLES)                %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    if [[ ! -f "${HISTORY_CSV}" || $(wc -l < "${HISTORY_CSV}") -le 1 ]]; then
        printf "%sNo historical telemetry samples recorded yet in %s%s\n" "${COLOR_YELLOW}" "${HISTORY_CSV}" "${COLOR_RESET}"
        pause_screen
        return 0
    fi

    printf "%-20s %-8s %-8s %-8s %-10s\n" "TIMESTAMP" "CPU %" "RAM %" "DISK %" "PROCS"
    printf "%s\n" "--------------------------------------------------------------------------------"

    # Tail last 20 records (excluding header)
    tail -n +2 "${HISTORY_CSV}" | tail -n 20 | while IFS=',' read -r ts cpu ram disk procs; do
        printf "%-20s %-8s %-8s %-8s %-10s\n" "${ts}" "${cpu}%" "${ram}%" "${disk}%" "${procs}"
    done

    printf "\n%s================ CPU UTILIZATION VISUAL BAR GRAPH (LAST 20) ================%s\n\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    tail -n +2 "${HISTORY_CSV}" | tail -n 20 | while IFS=',' read -r ts cpu ram disk procs; do
        local int_cpu
        int_cpu="$(awk -v c="${cpu}" 'BEGIN { printf "%d", c + 0.5 }')"
        local bars=$(( int_cpu / 4 )) # Scale 100% to 25 characters
        local bar_str=""
        for ((i=0; i<bars; i++)); do bar_str="${bar_str}#"; done

        local bar_color="${COLOR_GREEN}"
        (( int_cpu >= 80 )) && bar_color="${COLOR_RED}"
        (( int_cpu >= 60 && int_cpu < 80 )) && bar_color="${COLOR_YELLOW}"

        printf "%s | %s%-25s%s %5.1f%%\n" "${ts:11:8}" "${bar_color}" "${bar_str}" "${COLOR_RESET}" "${cpu}"
    done

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    pause_screen
}

# ==============================================================================
# 4. Generate Comprehensive System Health Audit Report
# OS Concept: System diagnostics audit trail generation for compliance and operations
# ==============================================================================
generate_health_report() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                 GENERATING COMPREHENSIVE SYSTEM HEALTH REPORT                  %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local report_file="${REPORTS_DIR}/health_${timestamp}.txt"

    printf "Compiling telemetry, hardware inventory, and security logs into:\n%s%s%s\n\n" \
        "${COLOR_BOLD}" "${report_file}" "${COLOR_RESET}"

    {
        printf "================================================================================\n"
        printf "               NEXADMIN - COMPREHENSIVE SYSTEM HEALTH & AUDIT REPORT            \n"
        printf "================================================================================\n"
        printf "Generated On : %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf "Hostname     : %s\n" "$(hostname 2>/dev/null || uname -n)"
        printf "Kernel       : %s\n" "$(uname -s -r -v -m)"
        printf "Uptime       : %s\n" "$(get_quick_uptime)"
        printf "Load Average : %s\n" "$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')"
        printf "Generated By : %s (UID: %s)\n\n" "${USER:-$(whoami)}" "${EUID:-$(id -u)}"

        printf "%s\n" "--------------------------------------------------------------------------------"
        printf "1. HARDWARE & CPU SPECIFICATIONS\n"
        printf "%s\n" "--------------------------------------------------------------------------------"
        get_system_specs
        printf "CPU Temperature : %s\n" "$(get_cpu_temperature)"
        printf "Power/Battery   : %s\n\n" "$(get_quick_battery)"

        printf "%s\n" "--------------------------------------------------------------------------------"
        printf "2. MEMORY & STORAGE ALLOCATION\n"
        printf "%s\n" "--------------------------------------------------------------------------------"
        printf "Current CPU Utilization : %s%%\n" "$(get_quick_cpu)"
        printf "Current RAM Utilization : %s%%\n" "$(get_quick_ram)"
        printf "\nPhysical Disks & Mounts:\n"
        df -h 2>/dev/null | grep -E '^/dev/' | grep -v '/snap/' || df -h 2>/dev/null

        printf "\n%s\n" "--------------------------------------------------------------------------------"
        printf "3. TOP 5 CPU CONSUMING PROCESSES\n"
        printf "%s\n" "--------------------------------------------------------------------------------"
        printf "%-8s %-12s %-8s %-8s %-25s\n" "PID" "USER" "%CPU" "%MEM" "COMMAND"
        ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | tail -n +2 | head -n 5

        printf "\n%s\n" "--------------------------------------------------------------------------------"
        printf "4. TOP 5 MEMORY CONSUMING PROCESSES\n"
        printf "%s\n" "--------------------------------------------------------------------------------"
        printf "%-8s %-12s %-8s %-8s %-25s\n" "PID" "USER" "%MEM" "%CPU" "COMMAND"
        ps -eo pid,user,%mem,%cpu,comm --sort=-%mem 2>/dev/null | tail -n +2 | head -n 5

        printf "\n%s\n" "--------------------------------------------------------------------------------"
        printf "5. ACTIVE THRESHOLD WARNINGS & RECENT ALERTS\n"
        printf "%s\n" "--------------------------------------------------------------------------------"
        printf "Current Active Alert Count: %s\n\n" "$(get_active_alert_count)"
        if [[ -f "${ALERT_LOG}" && -s "${ALERT_LOG}" ]]; then
            printf "Last 5 Recorded Alerts:\n"
            tail -n 5 "${ALERT_LOG}"
        else
            printf "No recent alerts logged.\n"
        fi

        printf "\n%s\n" "--------------------------------------------------------------------------------"
        printf "6. RECENT LOGIN ACTIVITY (LAST 5 SESSIONS)\n"
        printf "%s\n" "--------------------------------------------------------------------------------"
        last -n 5 2>/dev/null || printf "Login accounting not accessible.\n"

        printf "\n%s\n" "--------------------------------------------------------------------------------"
        printf "7. NETWORK INTERFACE CONFIGURATIONS\n"
        printf "%s\n" "--------------------------------------------------------------------------------"
        ip -brief addr 2>/dev/null || ifconfig -a 2>/dev/null || printf "Network info unavailable.\n"

        printf "\n================================================================================\n"
        printf "                          END OF SYSTEM HEALTH REPORT                           \n"
        printf "================================================================================\n"
    } > "${report_file}"

    log_action "Generated System Health Report: $(basename "${report_file}")"
    printf "%s[SUCCESS] Comprehensive health report saved to:%s\n%s\n\n" \
        "${COLOR_GREEN}" "${COLOR_RESET}" "${report_file}"

    pause_screen
}

# ==============================================================================
# 5. Export History CSV
# OS Concept: Audit data export for external visualization or spreadsheet processing
# ==============================================================================
export_history_csv() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                       EXPORT TELEMETRY HISTORY TO CSV                          %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    if [[ ! -f "${HISTORY_CSV}" || ! -s "${HISTORY_CSV}" ]]; then
        printf "%s[NOTICE] No telemetry history file exists to export.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local default_dest="${REPORTS_DIR}/telemetry_export_${timestamp}.csv"

    printf "Enter target export file path [%s]: " "${default_dest}"
    read -r user_dest
    local export_file="${user_dest:-${default_dest}}"

    if cp "${HISTORY_CSV}" "${export_file}" 2>/dev/null; then
        log_action "Exported telemetry CSV to ${export_file}"
        printf "%s[SUCCESS] Exported %d telemetry records to:%s\n%s\n" \
            "${COLOR_GREEN}" "$(wc -l < "${export_file}")" "${COLOR_RESET}" "${export_file}"
    else
        printf "%s[ERROR] Failed to write export file.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
    fi

    pause_screen
}

# ==============================================================================
# History & Reports Interactive Menu
# ==============================================================================
menu_history_reports() {
    log_action "Accessed History & Reports"
    local r_choice=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                  NEXADMIN - HISTORICAL METRICS & REPORTS                       %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        
        local rec_status
        if is_history_recorder_running; then
            local r_pid
            r_pid="$(cat "${RECORDER_PID_FILE}")"
            rec_status="${COLOR_GREEN}ACTIVE (PID: ${r_pid}, every ${HISTORY_RECORD_INTERVAL:-30}s)${COLOR_RESET}"
        else
            rec_status="${COLOR_DIM}STOPPED${COLOR_RESET}"
        fi

        printf " History Recorder Daemon: %s\n" "${rec_status}"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "  1) Capture Single Telemetry Snapshot Now\n"
        printf "  2) View Telemetry Table & ASCII Bar Chart (Last 20)\n"
        printf "  3) Start Background Telemetry Recorder Daemon\n"
        printf "  4) Stop Background Telemetry Recorder Daemon\n"
        printf "  5) Generate Comprehensive System Health Audit Report (.txt)\n"
        printf "  6) Export Telemetry Records to Custom CSV File\n"
        printf "  7) View Internal Toolkit Activity Audit Trail\n"
        printf "  0) Back to Main Menu\n"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-7]: "
        read -r r_choice

        case "${r_choice}" in
            1)
                record_history_snapshot
                printf "%s[SUCCESS] Telemetry snapshot captured and logged.%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
                sleep 1
                ;;
            2)
                view_history_table_and_graph
                ;;
            3)
                start_history_recorder
                sleep 1
                ;;
            4)
                stop_history_recorder
                sleep 1
                ;;
            5)
                generate_health_report
                ;;
            6)
                export_history_csv
                ;;
            7)
                view_nexadmin_log
                ;;
            0)
                break
                ;;
            *)
                printf "%sInvalid choice! Choose 0-7.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}
