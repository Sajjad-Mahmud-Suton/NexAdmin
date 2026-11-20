#!/usr/bin/env bash
# ==============================================================================
# File: modules/alert.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: Autonomous Alert & Health Monitoring Engine. Evaluates telemetry
#          against threshold parameters, writes structured alerts to disk,
#          and manages a background daemon process.
# ==============================================================================

ALERT_LOG="${BASE_DIR}/data/alerts.log"
ALERT_PID_FILE="${BASE_DIR}/data/.alert_daemon.pid"

# ==============================================================================
# Dynamic Active Alert Counter
# OS Concept: Evaluates current telemetry state to determine active warning count
# ==============================================================================
get_active_alert_count() {
    local count=0
    local cpu_val ram_val disk_val load_val bat_val

    # Ensure config values are present
    local c_thresh="${CPU_THRESHOLD:-80}"
    local r_thresh="${RAM_THRESHOLD:-85}"
    local d_thresh="${DISK_THRESHOLD:-90}"
    local b_thresh="${BATTERY_THRESHOLD:-20}"
    local l_thresh="${LOAD_THRESHOLD:-2.0}"

    # Evaluate CPU
    cpu_val="$(get_quick_cpu)"
    if num_gte "${cpu_val}" "${c_thresh}"; then
        (( count++ ))
    fi

    # Evaluate RAM
    ram_val="$(get_quick_ram)"
    if num_gte "${ram_val}" "${r_thresh}"; then
        (( count++ ))
    fi

    # Evaluate Disk
    disk_val="$(get_quick_disk)"
    if is_number "${disk_val}" && (( disk_val >= d_thresh )); then
        (( count++ ))
    fi

    # Evaluate Load
    load_val="$(get_quick_load)"
    if num_gte "${load_val}" "${l_thresh}"; then
        (( count++ ))
    fi

    # Evaluate Battery (only if battery is physically present and discharging)
    for bat in /sys/class/power_supply/BAT*; do
        if [[ -r "${bat}/capacity" && -r "${bat}/status" ]]; then
            local stat cap
            stat="$(cat "${bat}/status" 2>/dev/null)"
            cap="$(cat "${bat}/capacity" 2>/dev/null)"
            if [[ "${stat}" == "Discharging" ]] && is_number "${cap}" && (( cap <= b_thresh )); then
                (( count++ ))
            fi
            break
        fi
    done

    echo "${count}"
}

# ==============================================================================
# Alert Evaluator & Logger
# OS Concept: Event logging and threshold alerting for proactive sysadmin notice
# ==============================================================================
check_alerts() {
    local is_interactive="${1:-true}" # true to print to stdout, false for daemon mode
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local violations=0

    local c_thresh="${CPU_THRESHOLD:-80}"
    local r_thresh="${RAM_THRESHOLD:-85}"
    local d_thresh="${DISK_THRESHOLD:-90}"
    local b_thresh="${BATTERY_THRESHOLD:-20}"
    local l_thresh="${LOAD_THRESHOLD:-2.0}"

    local cpu_val ram_val disk_val load_val
    cpu_val="$(get_quick_cpu)"
    ram_val="$(get_quick_ram)"
    disk_val="$(get_quick_disk)"
    load_val="$(get_quick_load)"

    # 1. Check CPU
    if num_gte "${cpu_val}" "${c_thresh}"; then
        (( violations++ ))
        local msg="High CPU Usage: ${cpu_val}% (Threshold: ${c_thresh}%)"
        printf "[%s] WARNING: %s\n" "${timestamp}" "${msg}" >> "${ALERT_LOG}" 2>/dev/null
        if [[ "${is_interactive}" == "true" ]]; then
            printf "%s[ALERT] %s%s\n" "${COLOR_RED}" "${msg}" "${COLOR_RESET}"
        fi
    fi

    # 2. Check RAM
    if num_gte "${ram_val}" "${r_thresh}"; then
        (( violations++ ))
        local msg="High Memory Usage: ${ram_val}% (Threshold: ${r_thresh}%)"
        printf "[%s] WARNING: %s\n" "${timestamp}" "${msg}" >> "${ALERT_LOG}" 2>/dev/null
        if [[ "${is_interactive}" == "true" ]]; then
            printf "%s[ALERT] %s%s\n" "${COLOR_RED}" "${msg}" "${COLOR_RESET}"
        fi
    fi

    # 3. Check Disk
    if is_number "${disk_val}" && (( disk_val >= d_thresh )); then
        (( violations++ ))
        local msg="Low Disk Space: ${disk_val}% used on root partition (Threshold: ${d_thresh}%)"
        printf "[%s] WARNING: %s\n" "${timestamp}" "${msg}" >> "${ALERT_LOG}" 2>/dev/null
        if [[ "${is_interactive}" == "true" ]]; then
            printf "%s[ALERT] %s%s\n" "${COLOR_RED}" "${msg}" "${COLOR_RESET}"
        fi
    fi

    # 4. Check Load Average
    if num_gte "${load_val}" "${l_thresh}"; then
        (( violations++ ))
        local msg="High System Load: ${load_val} (Threshold: ${l_thresh})"
        printf "[%s] WARNING: %s\n" "${timestamp}" "${msg}" >> "${ALERT_LOG}" 2>/dev/null
        if [[ "${is_interactive}" == "true" ]]; then
            printf "%s[ALERT] %s%s\n" "${COLOR_YELLOW}" "${msg}" "${COLOR_RESET}"
        fi
    fi

    # 5. Check Battery
    for bat in /sys/class/power_supply/BAT*; do
        if [[ -r "${bat}/capacity" ]]; then
            local stat cap
            stat="$(cat "${bat}/status" 2>/dev/null)"
            cap="$(cat "${bat}/capacity" 2>/dev/null)"
            if [[ "${stat}" == "Discharging" ]] && is_number "${cap}" && (( cap <= b_thresh )); then
                (( violations++ ))
                local msg="Low Battery Level: ${cap}% discharging (Threshold: ${b_thresh}%)"
                printf "[%s] WARNING: %s\n" "${timestamp}" "${msg}" >> "${ALERT_LOG}" 2>/dev/null
                if [[ "${is_interactive}" == "true" ]]; then
                    printf "%s[ALERT] %s%s\n" "${COLOR_RED}" "${msg}" "${COLOR_RESET}"
                fi
            fi
            break
        fi
    done

    if [[ "${is_interactive}" == "true" && ${violations} -eq 0 ]]; then
        printf "%s[ALL CLEAR] All monitored system metrics are operating within normal parameters.%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
    fi

    return "${violations}"
}

# ==============================================================================
# Background Alert Daemon
# OS Concept: Daemon process management via fork and background execution (&)
# ==============================================================================
is_alert_daemon_running() {
    if [[ -f "${ALERT_PID_FILE}" ]]; then
        local pid
        pid="$(cat "${ALERT_PID_FILE}" 2>/dev/null)"
        if is_number "${pid}" && is_pid "${pid}"; then
            return 0
        fi
    fi
    return 1
}

start_alert_daemon() {
    if is_alert_daemon_running; then
        local existing_pid
        existing_pid="$(cat "${ALERT_PID_FILE}")"
        printf "%s[NOTICE] Alert daemon is already running (PID: %s).%s\n" "${COLOR_YELLOW}" "${existing_pid}" "${COLOR_RESET}"
        return 0
    fi

    local interval="${ALERT_CHECK_INTERVAL:-10}"

    # Spawn detached background monitoring loop
    (
        while true; do
            check_alerts "false"
            sleep "${interval}"
        done
    ) >/dev/null 2>&1 &

    local daemon_pid=$!
    echo "${daemon_pid}" > "${ALERT_PID_FILE}"
    log_action "Started background alert daemon (PID: ${daemon_pid}, interval: ${interval}s)"
    printf "%s[SUCCESS] Background alert monitor daemon started (PID: %s).%s\n" "${COLOR_GREEN}" "${daemon_pid}" "${COLOR_RESET}"
}

stop_alert_daemon() {
    if ! is_alert_daemon_running; then
        printf "%s[NOTICE] Alert daemon is not currently running.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        rm -f "${ALERT_PID_FILE}" 2>/dev/null || true
        return 0
    fi

    local daemon_pid
    daemon_pid="$(cat "${ALERT_PID_FILE}" 2>/dev/null)"

    if is_number "${daemon_pid}" && is_pid "${daemon_pid}"; then
        kill -15 "${daemon_pid}" 2>/dev/null || kill -9 "${daemon_pid}" 2>/dev/null || true
        log_action "Stopped background alert daemon (PID: ${daemon_pid})"
        printf "%s[SUCCESS] Background alert daemon (PID: %s) stopped.%s\n" "${COLOR_GREEN}" "${daemon_pid}" "${COLOR_RESET}"
    fi

    rm -f "${ALERT_PID_FILE}" 2>/dev/null || true
}

# ==============================================================================
# Alerts Interactive Menu
# ==============================================================================
menu_alerts() {
    log_action "Accessed Alerts Menu"
    local alert_choice=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                 NEXADMIN - AUTONOMOUS ALERT & HEALTH MONITOR                   %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        
        local daemon_status
        if is_alert_daemon_running; then
            local d_pid
            d_pid="$(cat "${ALERT_PID_FILE}")"
            daemon_status="${COLOR_GREEN}RUNNING (PID: ${d_pid})${COLOR_RESET}"
        else
            daemon_status="${COLOR_DIM}STOPPED${COLOR_RESET}"
        fi

        printf " Daemon Status: %s | Active Metric Alerts: %s%s%s\n" \
            "${daemon_status}" "${COLOR_BOLD}" "$(get_active_alert_count)" "${COLOR_RESET}"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "  1) Run Health & Threshold Audit Now\n"
        printf "  2) View Last 10 Recorded Alerts\n"
        printf "  3) Clear Alert History Log\n"
        printf "  4) Start Background Alert Daemon\n"
        printf "  5) Stop Background Alert Daemon\n"
        printf "  0) Back to Main Menu\n"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-5]: "
        read -r alert_choice

        case "${alert_choice}" in
            1)
                clear
                printf "%s================ SYSTEM HEALTH & THRESHOLD AUDIT ================%s\n\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
                printf "Checking active thresholds (CPU: %s%%, RAM: %s%%, Disk: %s%%, Load: %s)...\n\n" \
                    "${CPU_THRESHOLD:-80}" "${RAM_THRESHOLD:-85}" "${DISK_THRESHOLD:-90}" "${LOAD_THRESHOLD:-2.0}"
                check_alerts "true"
                pause_screen
                ;;
            2)
                clear
                printf "%s==================== LAST 10 RECORDED ALERTS ====================%s\n\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
                if [[ -f "${ALERT_LOG}" && -s "${ALERT_LOG}" ]]; then
                    tail -n 10 "${ALERT_LOG}"
                else
                    printf "No historical alerts recorded yet.\n"
                fi
                pause_screen
                ;;
            3)
                if confirm "Are you sure you want to clear the alert history log?"; then
                    > "${ALERT_LOG}"
                    log_action "Cleared alert log"
                    printf "%s[SUCCESS] Alert history log cleared.%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            4)
                start_alert_daemon
                sleep 1.2
                ;;
            5)
                stop_alert_daemon
                sleep 1.2
                ;;
            0)
                break
                ;;
            *)
                printf "%sInvalid choice! Please choose 0-5.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}
