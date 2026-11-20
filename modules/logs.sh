#!/usr/bin/env bash
# ==============================================================================
# File: modules/logs.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: System & Security Log Viewer. Parses authentication logs for brute
#          force failed login attacks, filters system logs by priority/keywords,
#          and displays the NexAdmin internal audit trail.
# ==============================================================================

# Determines the active security authentication log path on Debian/Ubuntu/RHEL
get_auth_log_path() {
    if [[ -r /var/log/auth.log ]]; then
        echo "/var/log/auth.log"
    elif [[ -r /var/log/secure ]]; then
        echo "/var/log/secure"
    else
        echo ""
    fi
}

# ==============================================================================
# 1. Failed Authentication & Brute Force Attack Auditor
# OS Concept: Security log forensics, intrusion detection via pattern recognition
# ==============================================================================
audit_failed_logins() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                   SECURITY AUDIT: FAILED LOGIN ATTEMPTS                        %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    local auth_log
    auth_log="$(get_auth_log_path)"

    if [[ -n "${auth_log}" ]]; then
        printf "Inspecting security log: %s%s%s\n\n" "${COLOR_BOLD}" "${auth_log}" "${COLOR_RESET}"

        local failed_total
        failed_total="$(grep -iE "failed password|authentication failure" "${auth_log}" 2>/dev/null | wc -l | tr -d ' ')"
        printf "Total Failed Authentication Events: %s%s%s\n\n" "${COLOR_RED}" "${failed_total}" "${COLOR_RESET}"

        printf "%s--- TOP SOURCE IP ADDRESSES FOR FAILED LOGINS ---%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        printf "%-8s %-25s\n" "COUNT" "SOURCE IP ADDRESS"
        printf "%s\n" "----------------------------------"

        # Extract IP addresses from failed login entries using grep, awk, sort, uniq -c, head
        local top_ips
        top_ips="$(grep -iE "failed password|authentication failure" "${auth_log}" 2>/dev/null | \
                   grep -oE "from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | awk '{print $2}' | \
                   sort | uniq -c | sort -nr | head -n 10 || true)"

        if [[ -n "${top_ips}" ]]; then
            echo "${top_ips}" | while read -r count ip; do
                printf "%-8s %-25s\n" "${count}" "${ip}"
            done
        else
            printf "No external IP addresses associated with failed attempts found.\n"
        fi

        printf "\n%s--- RECENT 10 FAILED LOGIN ATTEMPTS ---%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        grep -iE "failed password|authentication failure" "${auth_log}" 2>/dev/null | tail -n 10 || printf "None\n"
    else
        # Fallback to journalctl if log file permissions restrict direct access
        if has_cmd journalctl; then
            printf "%s[NOTICE] Direct access to /var/log/auth.log is restricted.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
            printf "Attempting extraction via systemd journald (journalctl)...\n\n"
            journalctl _COMM=sshd -n 15 --no-pager 2>/dev/null | grep -iE "failed|failure" || \
                printf "No accessible security logs available without superuser privileges.\n"
        else
            printf "%s[N/A] Authentication log (/var/log/auth.log or /var/log/secure) unreadable.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
            printf "Please re-run NexAdmin with sudo to view privileged system security logs.\n"
        fi
    fi

    pause_screen
}

# ==============================================================================
# 2. Filter System Logs by Keyword or Error/Warning
# OS Concept: Systemd journal filtering and syslog diagnostic tracing
# ==============================================================================
filter_system_logs() {
    local filter_type="$1" # keyword or priority

    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                         SYSTEM LOG DIAGNOSTIC FILTER                           %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    if [[ "${filter_type}" == "priority" ]]; then
        printf "%sDisplaying System Errors & Warnings (Priority: err, warning):%s\n\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        if has_cmd journalctl; then
            journalctl -p 3..4 -n 25 --no-pager 2>/dev/null || printf "Unable to read journalctl.\n"
        elif [[ -r /var/log/syslog ]]; then
            grep -iE "error|warn" /var/log/syslog 2>/dev/null | tail -n 25
        else
            printf "%s[N/A] System logs unavailable without elevated permissions.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        fi
    else
        printf "Enter keyword to search in system logs (e.g., kernel, memory, network, cron): "
        read -r kw
        kw="$(echo "${kw}" | tr -cd 'A-Za-z0-9_.-')"
        if [[ -z "${kw}" ]]; then
            printf "%sKeyword cannot be empty.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
            pause_screen
            return 1
        fi

        printf "\n%sMatching log entries for '%s':%s\n\n" "${COLOR_BOLD}" "${kw}" "${COLOR_RESET}"
        if has_cmd journalctl; then
            journalctl -g "${kw}" -n 25 --no-pager 2>/dev/null || printf "No matches found in journalctl.\n"
        elif [[ -r /var/log/syslog ]]; then
            grep -i "${kw}" /var/log/syslog 2>/dev/null | tail -n 25
        else
            printf "%s[N/A] System log files unreadable without elevated permissions.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        fi
    fi

    pause_screen
}

# ==============================================================================
# 3. NexAdmin Audit Trail Viewer
# OS Concept: Local application audit trail inspection
# ==============================================================================
view_nexadmin_log() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                       NEXADMIN INTERNAL ACTIVITY AUDIT LOG                     %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    local log_path="${BASE_DIR}/nexadmin.log"
    printf "Log File: %s\n\n" "${log_path}"

    if [[ -f "${log_path}" && -s "${log_path}" ]]; then
        tail -n 25 "${log_path}"
    else
        printf "No internal activities recorded yet.\n"
    fi

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    pause_screen
}

# ==============================================================================
# Log Viewer Interactive Menu
# ==============================================================================
menu_log_viewer() {
    log_action "Accessed Log Viewer"
    local l_choice=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                    NEXADMIN - SYSTEM & SECURITY LOG VIEWER                     %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  1) Security Forensics: Failed Login Attempts & Top Attacking IPs\n"
        printf "  2) System Health: Filter Errors and Warnings (priority 3-4)\n"
        printf "  3) Search System Logs by Custom Keyword\n"
        printf "  4) View NexAdmin Toolkit Audit Trail (nexadmin.log)\n"
        printf "  0) Back to Main Menu\n"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-4]: "
        read -r l_choice

        case "${l_choice}" in
            1) audit_failed_logins ;;
            2) filter_system_logs "priority" ;;
            3) filter_system_logs "keyword" ;;
            4) view_nexadmin_log ;;
            0) break ;;
            *)
                printf "%sInvalid choice! Choose 0-4.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}
