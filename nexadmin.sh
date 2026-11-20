#!/usr/bin/env bash
# ==============================================================================
# File: nexadmin.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Version: 1.0.0
# Description: Main entry point for NexAdmin. Handles argument parsing,
#              authentication, live dashboard summary, and primary menu navigation.
# ==============================================================================

set -o pipefail

# Resolve script directory to enable running from any working directory
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
export BASE_DIR="${SCRIPT_DIR}"

# Source shared library
if [[ -f "${BASE_DIR}/lib/common.sh" ]]; then
    # shellcheck source=lib/common.sh
    source "${BASE_DIR}/lib/common.sh"
else
    printf "Error: Missing library ${BASE_DIR}/lib/common.sh\n" >&2
    exit 1
fi

# Load configuration
load_config "${BASE_DIR}/config.conf"

# Source all functional modules
MODULES=(
    "monitor.sh"
    "process.sh"
    "procmgr.sh"
    "alert.sh"
    "backup.sh"
    "users.sh"
    "logs.sh"
    "network.sh"
    "report.sh"
)

for mod in "${MODULES[@]}"; do
    mod_path="${BASE_DIR}/modules/${mod}"
    if [[ -f "${mod_path}" ]]; then
        # shellcheck source=/dev/null
        source "${mod_path}"
    else
        printf "%sError: Missing required module: %s%s\n" "${COLOR_RED}" "${mod_path}" "${COLOR_RESET}" >&2
        exit 1
    fi
done

# Ensure required directories exist
mkdir -p "${BASE_DIR}/data" "${BASE_DIR}/backups" "${BASE_DIR}/reports"

# ==============================================================================
# Signal Trap & Terminal Restoration
# OS Concept: Signal handling (SIGINT, SIGTERM) ensures graceful shutdown,
#             cleans background tasks, and restores terminal echo.
# ==============================================================================
cleanup_and_exit() {
    # Restore terminal echo in case trapped during hidden password read
    stty echo 2>/dev/null || true
    printf "%s\n" "${COLOR_RESET}"
    
    # Check if a background alert process was started and record exit
    log_action "Session terminated cleanly"
    exit 0
}
trap cleanup_and_exit INT TERM EXIT

# ==============================================================================
# Command Line Argument Parsing
# ==============================================================================
show_help() {
    cat << EOF
NexAdmin - Linux System Administration & Monitoring Toolkit
Usage: $(basename "$0") [OPTIONS]

Options:
  -h, --help        Display this help message and exit
  -v, --version     Display version information and exit

Security Policy:
  Bypassing authentication (--no-login) is strictly disallowed by security rules.

Project Components:
  - Real-time CPU, RAM, Disk, Battery, and Temperature monitoring (/proc & /sys)
  - Process Inspection, Top resource consumers, and Process Signals (SIGTERM/SIGKILL/SIGSTOP/SIGCONT)
  - Autonomous Threshold Alerting & Background Daemon
  - Full & Incremental Tar/Gzip Backups with MD5 Verification & Crontab automation
  - User and Group Administration with password aging and login auditing
  - Log analysis and Network Socket / Bandwidth inspector
EOF
}

show_version() {
    printf "NexAdmin v1.0.0 (Linux System Administration and Monitoring Toolkit)\n"
    printf "Developed for University Operating Systems Laboratory Defense.\n"
}

for arg in "$@"; do
    case "${arg}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        --no-login)
            printf "%sSecurity Error: --no-login is strictly prohibited by NexAdmin security policy.%s\n" "${COLOR_RED}" "${COLOR_RESET}" >&2
            log_action "SECURITY: Unauthorized attempt to bypass login with --no-login"
            exit 1
            ;;
        *)
            printf "%sUnknown argument: %s%s\n" "${COLOR_RED}" "${arg}" "${COLOR_RESET}" >&2
            printf "Use --help for usage instructions.\n"
            exit 1
            ;;
    esac
done

# ==============================================================================
# Authentication & Access Control
# OS Concept: Cryptographic password hashing (SHA-256) and strict permission
#             masks (chmod 600) protect credentials at rest.
# ==============================================================================
authenticate_user() {
    local auth_file="${BASE_DIR}/data/.password.hash"
    local input_pw=""
    local confirm_pw=""
    local input_hash=""
    local stored_hash=""
    local attempts=0
    local max_attempts=3

    # First run setup
    if [[ ! -f "${auth_file}" ]]; then
        clear
        printf "%s=================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                NEXADMIN FIRST-TIME INITIALIZATION              %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s=================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "No administrator password configured. Please establish a secure master password.\n\n"

        while true; do
            printf "%sEnter new master password: %s" "${COLOR_YELLOW}" "${COLOR_RESET}"
            read -r -s input_pw
            printf "\n"

            if [[ -z "${input_pw}" ]]; then
                printf "%sPassword cannot be empty. Please try again.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                continue
            fi

            printf "%sConfirm master password: %s" "${COLOR_YELLOW}" "${COLOR_RESET}"
            read -r -s confirm_pw
            printf "\n"

            if [[ "${input_pw}" != "${confirm_pw}" ]]; then
                printf "%sPasswords do not match! Please try again.%s\n\n" "${COLOR_RED}" "${COLOR_RESET}"
            else
                # Generate SHA-256 hash
                printf '%s' "${input_pw}" | sha256sum | awk '{print $1}' > "${auth_file}"
                chmod 600 "${auth_file}" 2>/dev/null || true
                log_action "Initial master password established"
                printf "%s\n[SUCCESS] Master password initialized. Welcome to NexAdmin!%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
                sleep 1
                break
            fi
        done
        return 0
    fi

    # Subsequent runs: Verify Password
    stored_hash="$(awk '{print $1}' "${auth_file}" 2>/dev/null)"

    while (( attempts < max_attempts )); do
        clear
        printf "%s=================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                     NEXADMIN AUTHENTICATION                    %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s=================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "User: %s%s%s\n" "${COLOR_BOLD}" "${USER:-$(whoami)}" "${COLOR_RESET}"
        printf "Please authenticate to access the administration toolkit.\n\n"

        printf "%sEnter password (%d attempts remaining): %s" "${COLOR_YELLOW}" "$(( max_attempts - attempts ))" "${COLOR_RESET}"
        read -r -s input_pw
        printf "\n"

        input_hash="$(printf '%s' "${input_pw}" | sha256sum | awk '{print $1}')"

        if [[ "${input_hash}" == "${stored_hash}" ]]; then
            log_action "Successful login authentication"
            printf "%s[ACCESS GRANTED] Identity verified successfully.%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
            sleep 0.8
            return 0
        else
            (( attempts++ ))
            log_action "Failed login attempt (${attempts}/${max_attempts})"
            printf "%s[ERROR] Incorrect password.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
            sleep 1
        fi
    done

    printf "\n%s[FATAL] Maximum authentication attempts exceeded. Exiting.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
    log_action "SECURITY: Account locked due to exceeding maximum login attempts"
    exit 1
}

# ==============================================================================
# Live Summary Dashboard Renderer
# OS Concept: Parsing Linux virtual filesystems (/proc/stat, /proc/meminfo,
#             /proc/loadavg) for instantaneous telemetry.
# ==============================================================================
render_dashboard_header() {
    local cpu_usage
    local ram_usage
    local disk_usage
    local battery_info
    local uptime_str
    local load_avg
    local total_procs
    local alert_count

    cpu_usage="$(get_quick_cpu)"
    ram_usage="$(get_quick_ram)"
    disk_usage="$(get_quick_disk)"
    battery_info="$(get_quick_battery)"
    uptime_str="$(get_quick_uptime)"
    load_avg="$(get_quick_load)"
    total_procs="$(get_total_processes_count)"
    alert_count="$(get_active_alert_count)"

    # Format colors based on thresholds
    local cpu_col="${COLOR_GREEN}"
    num_gte "${cpu_usage}" "${CPU_THRESHOLD:-80}" && cpu_col="${COLOR_RED}"

    local ram_col="${COLOR_GREEN}"
    num_gte "${ram_usage}" "${RAM_THRESHOLD:-85}" && ram_col="${COLOR_RED}"

    local disk_col="${COLOR_GREEN}"
    num_gte "${disk_usage}" "${DISK_THRESHOLD:-90}" && disk_col="${COLOR_RED}"

    local alert_col="${COLOR_GREEN}"
    if (( alert_count > 0 )); then
        alert_col="${COLOR_RED}"
    fi

    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s             NEXADMIN - LINUX SYSTEM ADMINISTRATION & MONITORING TOOLKIT       %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf " CPU: %s%s%%%s | RAM: %s%s%%%s | Disk: %s%s%%%s | Battery: %s%s%s | Uptime: %s%s%s\n" \
        "${cpu_col}" "${cpu_usage}" "${COLOR_RESET}" \
        "${ram_col}" "${ram_usage}" "${COLOR_RESET}" \
        "${disk_col}" "${disk_usage}" "${COLOR_RESET}" \
        "${COLOR_BOLD}" "${battery_info}" "${COLOR_RESET}" \
        "${COLOR_BOLD}" "${uptime_str}" "${COLOR_RESET}"
    printf " Load Avg: %s%s%s | Processes: %s%s%s | Active Alerts: %s%s%s\n" \
        "${COLOR_BOLD}" "${load_avg}" "${COLOR_RESET}" \
        "${COLOR_BOLD}" "${total_procs}" "${COLOR_RESET}" \
        "${alert_col}" "${alert_count}" "${COLOR_RESET}"
    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
}

# ==============================================================================
# Settings Menu (Option 12)
# ==============================================================================
menu_settings() {
    local choice=""
    while true; do
        clear
        printf "%s=================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                       TOOLKIT SETTINGS                         %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s=================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf " 1) CPU Alert Threshold       : %s%s%%%s\n" "${COLOR_BOLD}" "${CPU_THRESHOLD:-80}" "${COLOR_RESET}"
        printf " 2) RAM Alert Threshold       : %s%s%%%s\n" "${COLOR_BOLD}" "${RAM_THRESHOLD:-85}" "${COLOR_RESET}"
        printf " 3) Disk Alert Threshold      : %s%s%%%s\n" "${COLOR_BOLD}" "${DISK_THRESHOLD:-90}" "${COLOR_RESET}"
        printf " 4) Battery Low Threshold     : %s%s%%%s\n" "${COLOR_BOLD}" "${BATTERY_THRESHOLD:-20}" "${COLOR_RESET}"
        printf " 5) Load Average Threshold    : %s%s%s\n" "${COLOR_BOLD}" "${LOAD_THRESHOLD:-2.0}" "${COLOR_RESET}"
        printf " 6) Live Refresh Interval     : %s%ss%s\n" "${COLOR_BOLD}" "${REFRESH_INTERVAL:-3}" "${COLOR_RESET}"
        printf " 7) Backup Retention Days     : %s%s days%s\n" "${COLOR_BOLD}" "${BACKUP_RETENTION_DAYS:-7}" "${COLOR_RESET}"
        printf " 8) Default Backup Directory  : %s%s%s\n" "${COLOR_BOLD}" "${DEFAULT_BACKUP_DIR:-/tmp}" "${COLOR_RESET}"
        printf " 9) Reset All to Defaults\n"
        printf " 0) Back to Main Menu\n"
        printf "%s-----------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-9]: "
        read -r choice

        case "${choice}" in
            1)
                printf "Enter new CPU alert threshold (1-100): "
                read -r val
                if is_number "${val}" && (( val >= 1 && val <= 100 )); then
                    save_config_val "CPU_THRESHOLD" "${val}"
                    log_action "Settings updated: CPU_THRESHOLD=${val}"
                else
                    printf "%sInvalid input! Must be integer 1-100.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            2)
                printf "Enter new RAM alert threshold (1-100): "
                read -r val
                if is_number "${val}" && (( val >= 1 && val <= 100 )); then
                    save_config_val "RAM_THRESHOLD" "${val}"
                    log_action "Settings updated: RAM_THRESHOLD=${val}"
                else
                    printf "%sInvalid input! Must be integer 1-100.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            3)
                printf "Enter new Disk alert threshold (1-100): "
                read -r val
                if is_number "${val}" && (( val >= 1 && val <= 100 )); then
                    save_config_val "DISK_THRESHOLD" "${val}"
                    log_action "Settings updated: DISK_THRESHOLD=${val}"
                else
                    printf "%sInvalid input! Must be integer 1-100.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            4)
                printf "Enter new Battery low threshold (1-100): "
                read -r val
                if is_number "${val}" && (( val >= 1 && val <= 100 )); then
                    save_config_val "BATTERY_THRESHOLD" "${val}"
                    log_action "Settings updated: BATTERY_THRESHOLD=${val}"
                else
                    printf "%sInvalid input! Must be integer 1-100.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            5)
                printf "Enter new Load threshold (e.g., 2.0): "
                read -r val
                if is_float_or_int "${val}"; then
                    save_config_val "LOAD_THRESHOLD" "${val}"
                    log_action "Settings updated: LOAD_THRESHOLD=${val}"
                else
                    printf "%sInvalid input! Must be positive number.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            6)
                printf "Enter new Live Refresh Interval in seconds (1-60): "
                read -r val
                if is_number "${val}" && (( val >= 1 && val <= 60 )); then
                    save_config_val "REFRESH_INTERVAL" "${val}"
                    log_action "Settings updated: REFRESH_INTERVAL=${val}"
                else
                    printf "%sInvalid input! Must be integer 1-60.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            7)
                printf "Enter new Backup Retention in days (1-365): "
                read -r val
                if is_number "${val}" && (( val >= 1 && val <= 365 )); then
                    save_config_val "BACKUP_RETENTION_DAYS" "${val}"
                    log_action "Settings updated: BACKUP_RETENTION_DAYS=${val}"
                else
                    printf "%sInvalid input! Must be integer 1-365.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            8)
                printf "Enter default backup directory path: "
                read -r val
                if [[ -d "${val}" ]]; then
                    save_config_val "DEFAULT_BACKUP_DIR" "${val}"
                    log_action "Settings updated: DEFAULT_BACKUP_DIR=${val}"
                else
                    printf "%sDirectory does not exist!%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1.2
                fi
                ;;
            9)
                if confirm "Are you sure you want to reset all settings to defaults?"; then
                    save_config_val "CPU_THRESHOLD" "80"
                    save_config_val "RAM_THRESHOLD" "85"
                    save_config_val "DISK_THRESHOLD" "90"
                    save_config_val "BATTERY_THRESHOLD" "20"
                    save_config_val "LOAD_THRESHOLD" "2.0"
                    save_config_val "REFRESH_INTERVAL" "3"
                    save_config_val "BACKUP_RETENTION_DAYS" "7"
                    save_config_val "DEFAULT_BACKUP_DIR" "/tmp/nexadmin_demo"
                    log_action "Settings reset to system defaults"
                    printf "%s[SUCCESS] Settings restored to factory defaults.%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            0)
                break
                ;;
            *)
                printf "%sInvalid selection! Please enter a number between 0 and 9.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# Main Menu Navigation Loop
# ==============================================================================
main_menu() {
    local choice=""

    while true; do
        render_dashboard_header

        printf "  %s1)%s Live System Monitor\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  %s2)%s Process List\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  %s3)%s Top 10 CPU / RAM Processes\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  %s4)%s Search Process / Process Details\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  %s5)%s Process Manager (Kill / Renice / Signals)\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  %s6)%s Network Info & Socket Inspector\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  %s7)%s Backup & Restore Manager\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  %s8)%s User & Group Management\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  %s9)%s System & Security Log Viewer\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf " %s10)%s Alerts & Threshold Monitor\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf " %s11)%s History & Health Reports\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf " %s12)%s Settings & Configuration\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf " %s13)%s Exit NexAdmin\n" "${COLOR_RED}" "${COLOR_RESET}"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Select an option [1-13]: "

        read -r choice

        # Input validation: check non-numeric or out of range
        if ! is_number "${choice}"; then
            printf "%s[ERROR] Non-numeric input. Please select a valid option (1-13).%s\n" "${COLOR_RED}" "${COLOR_RESET}"
            sleep 1.2
            continue
        fi

        case "${choice}" in
            1)  menu_system_monitor ;;
            2)  menu_process_list ;;
            3)  menu_top_processes ;;
            4)  menu_search_process ;;
            5)  menu_process_manager ;;
            6)  menu_network_info ;;
            7)  menu_backup_restore ;;
            8)  menu_user_management ;;
            9)  menu_log_viewer ;;
            10) menu_alerts ;;
            11) menu_history_reports ;;
            12) menu_settings ;;
            13)
                if confirm "Are you sure you want to exit NexAdmin?" "y"; then
                    log_action "User logged out of NexAdmin"
                    printf "\n%sThank you for using NexAdmin. Goodbye!%s\n\n" "${COLOR_GREEN}" "${COLOR_RESET}"
                    exit 0
                fi
                ;;
            *)
                printf "%s[ERROR] Choice out of range! Please choose between 1 and 13.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1.2
                ;;
        esac
    done
}

# ==============================================================================
# Script Execution Entry Point
# ==============================================================================
main() {
    # Check execution privileges
    log_action "NexAdmin started"

    # Authenticate before accessing toolkit
    authenticate_user

    # Launch dashboard main menu loop
    main_menu
}

main "$@"
