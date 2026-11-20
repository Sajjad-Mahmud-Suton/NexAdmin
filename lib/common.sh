#!/usr/bin/env bash
# ==============================================================================
# File: lib/common.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: Shared helper utilities, ANSI color definitions, input validation,
#          logging, and system sanity checks.
# ==============================================================================

# Ensure BASE_DIR is defined
BASE_DIR="${BASE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)}"

# ==============================================================================
# 1. ANSI Color & Formatting Setup (with NO_COLOR & terminal check)
# OS Concept: ANSI escape sequences control terminal text styling.
# ==============================================================================
init_colors() {
    if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
        COLOR_RESET=$'\033[0m'
        COLOR_BOLD=$'\033[1m'
        COLOR_DIM=$'\033[2m'
        COLOR_RED=$'\033[0;31m'
        COLOR_GREEN=$'\033[0;32m'
        COLOR_YELLOW=$'\033[0;33m'
        COLOR_BLUE=$'\033[0;34m'
        COLOR_MAGENTA=$'\033[0;35m'
        COLOR_CYAN=$'\033[0;36m'
        COLOR_WHITE=$'\033[1;37m'
    else
        COLOR_RESET=""
        COLOR_BOLD=""
        COLOR_DIM=""
        COLOR_RED=""
        COLOR_GREEN=""
        COLOR_YELLOW=""
        COLOR_BLUE=""
        COLOR_MAGENTA=""
        COLOR_CYAN=""
        COLOR_WHITE=""
    fi
}
init_colors

# ==============================================================================
# 2. Activity Logging
# OS Concept: Audit logging tracks operations with timestamps and user context.
# ==============================================================================
log_action() {
    local action="$1"
    local log_file="${BASE_DIR}/nexadmin.log"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local actor="${USER:-$(whoami 2>/dev/null || echo "unknown")}"

    # Ensure log file exists
    if [[ ! -f "${log_file}" ]]; then
        touch "${log_file}" 2>/dev/null || return 0
        chmod 644 "${log_file}" 2>/dev/null || true
    fi

    printf "[%s] USER:%s ACTION:%s\n" "${timestamp}" "${actor}" "${action}" >> "${log_file}" 2>/dev/null || true
}

# ==============================================================================
# 3. Input Validation Helpers
# OS Concept: Input sanitization protects system commands from malicious input.
# ==============================================================================

# Checks whether a given string is a non-negative integer
is_number() {
    local val="$1"
    [[ "${val}" =~ ^[0-9]+$ ]]
}

# Checks whether a given string is a valid positive floating point or integer
is_float_or_int() {
    local val="$1"
    [[ "${val}" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

# Compares two numbers (supports floats and ints): returns 0 (true) if $1 >= $2
num_gte() {
    local val1="$1"
    local val2="$2"
    awk -v a="${val1}" -v b="${val2}" 'BEGIN { exit !(a + 0 >= b + 0) }'
}

# Compares two numbers (supports floats and ints): returns 0 (true) if $1 <= $2
num_lte() {
    local val1="$1"
    local val2="$2"
    awk -v a="${val1}" -v b="${val2}" 'BEGIN { exit !(a + 0 <= b + 0) }'
}

# Checks whether a PID is an existing positive integer
is_pid() {
    local pid="$1"
    if ! is_number "${pid}"; then
        return 1
    fi
    if [[ "${pid}" -le 0 ]]; then
        return 1
    fi
    # Check if process directory exists in /proc
    [[ -d "/proc/${pid}" ]]
}

# Validates standard Linux usernames (POSIX username constraints)
is_valid_username() {
    local username="$1"
    [[ "${username}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

# ==============================================================================
# 4. User Interaction Helpers
# ==============================================================================

# Prompts for yes/no confirmation. Returns 0 for yes, 1 for no.
confirm() {
    local prompt_msg="$1"
    local default_choice="${2:-n}" # y or n
    local response

    if [[ "${default_choice}" =~ ^[Yy]$ ]]; then
        printf "%s%s [Y/n]: %s" "${COLOR_YELLOW}" "${prompt_msg}" "${COLOR_RESET}"
    else
        printf "%s%s [y/N]: %s" "${COLOR_YELLOW}" "${prompt_msg}" "${COLOR_RESET}"
    fi

    read -r response
    response="${response:-${default_choice}}"

    case "${response}" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# Pauses screen execution until user hits Enter
pause_screen() {
    local dummy
    printf "\n%sPress [Enter] to return to the menu...%s" "${COLOR_DIM}" "${COLOR_RESET}"
    read -r dummy
}

# ==============================================================================
# 5. Visual Rendering Helpers
# OS Concept: Text-mode progress visualization with ANSI color scaling.
# ==============================================================================
progress_bar() {
    local percent="${1:-0}"
    local width="${2:-20}"

    # Clamp percentage between 0 and 100
    if (( $(echo "${percent} > 100" | awk '{print ($1 > 100)}') )); then
        percent=100
    elif (( $(echo "${percent} < 0" | awk '{print ($1 < 0)}') )); then
        percent=0
    fi

    local int_percent
    int_percent="$(awk -v p="${percent}" 'BEGIN { printf "%d", p + 0.5 }')"
    local filled=$(( int_percent * width / 100 ))
    local empty=$(( width - filled ))

    local fill_str=""
    local empty_str=""
    local i

    for ((i=0; i<filled; i++)); do fill_str="${fill_str}#"; done
    for ((i=0; i<empty; i++)); do empty_str="${empty_str}-"; done

    # Color code according to load level
    local bar_color="${COLOR_GREEN}"
    if (( int_percent >= 90 )); then
        bar_color="${COLOR_RED}"
    elif (( int_percent >= 70 )); then
        bar_color="${COLOR_YELLOW}"
    fi

    printf "[%s%s%s%s] %3d%%" "${bar_color}" "${fill_str}" "${COLOR_DIM}${empty_str}" "${COLOR_RESET}" "${int_percent}"
}

# ==============================================================================
# 6. Privilege and Command Checks
# OS Concept: Linux privilege separation (Root vs Unprivileged User).
# ==============================================================================
is_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

require_root_or_warn() {
    local action_name="${1:-this administrative operation}"
    if ! is_root; then
        printf "\n%s[NOTICE] %s requires superuser (root) privileges.%s\n" "${COLOR_YELLOW}" "${action_name}" "${COLOR_RESET}"
        printf "%sPlease execute the command with 'sudo ./nexadmin.sh' if you encounter permission errors.%s\n\n" "${COLOR_DIM}" "${COLOR_RESET}"
        return 1
    fi
    return 0
}

# ==============================================================================
# 7. Safe Configuration Management
# OS Concept: Safe file-based key-value configuration parsing and update.
# ==============================================================================
load_config() {
    local conf_file="${1:-${BASE_DIR}/config.conf}"

    if [[ ! -f "${conf_file}" ]]; then
        return 1
    fi

    # Read line-by-line safely without eval to prevent command injection
    while IFS='=' read -r key val || [[ -n "${key}" ]]; do
        # Trim leading/trailing whitespace
        key="$(echo "${key}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        # Ignore comments and empty lines
        [[ "${key}" =~ ^#.*$ ]] && continue
        [[ -z "${key}" ]] && continue

        val="$(echo "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        # Strip potential surrounding quotes
        val="${val%\"}"
        val="${val#\"}"
        val="${val%\'}"
        val="${val#\'}"

        # Export recognized configuration keys only
        case "${key}" in
            CPU_THRESHOLD|RAM_THRESHOLD|DISK_THRESHOLD|BATTERY_THRESHOLD|\
            LOAD_THRESHOLD|REFRESH_INTERVAL|ALERT_CHECK_INTERVAL|\
            HISTORY_RECORD_INTERVAL|BACKUP_RETENTION_DAYS|DEFAULT_BACKUP_DIR)
                export "${key}=${val}"
                ;;
        esac
    done < "${conf_file}"
}

save_config_val() {
    local key="$1"
    local new_val="$2"
    local conf_file="${3:-${BASE_DIR}/config.conf}"

    if [[ ! -f "${conf_file}" ]]; then
        touch "${conf_file}"
    fi

    # Sanitize key and new_val against delimiter injection
    key="$(echo "${key}" | tr -cd 'A-Za-z0-9_')"
    new_val="$(echo "${new_val}" | sed -e 's/[\/&]/\\&/g')"

    if grep -q "^[[:space:]]*${key}=" "${conf_file}"; then
        sed -i "s|^[[:space:]]*${key}=.*|${key}=${new_val}|" "${conf_file}"
    else
        printf "%s=%s\n" "${key}" "${new_val}" >> "${conf_file}"
    fi

    # Reload into active environment
    load_config "${conf_file}"
}
