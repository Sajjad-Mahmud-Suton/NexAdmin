#!/usr/bin/env bash
# ==============================================================================
# File: modules/users.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: User & Group Management and Identity Auditing. Manages user accounts,
#          group memberships, password aging policies, and active sessions.
# ==============================================================================

# ==============================================================================
# Read-Only Identity Queries (Accessible to All Users)
# OS Concept: POSIX user database (/etc/passwd, /etc/group), utmp/wtmp accounting
# ==============================================================================

# Lists standard human interactive users (UID >= 1000)
# OS Concept: Conventional UID separation (0 = root, 1-999 = system, >=1000 = regular users)
list_regular_users() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                       SYSTEM USER ACCOUNTS (UID >= 1000)                       %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%-18s %-6s %-6s %-22s %-20s\n" "USERNAME" "UID" "GID" "HOME DIRECTORY" "LOGIN SHELL"
    printf "%s\n" "--------------------------------------------------------------------------------"

    awk -F: '$3 >= 1000 && $3 < 65534 { printf "%-18s %-6s %-6s %-22s %-20s\n", $1, $3, $4, $6, $7 }' /etc/passwd

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    pause_screen
}

# Lists local user groups from /etc/group
# OS Concept: UNIX discretionary access control group memberships
list_system_groups() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                       SYSTEM GROUPS (GID >= 1000)                              %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%-20s %-8s %-45s\n" "GROUP NAME" "GID" "MEMBER USERS"
    printf "%s\n" "--------------------------------------------------------------------------------"

    awk -F: '$3 >= 1000 && $3 < 65534 { printf "%-20s %-8s %-45s\n", $1, $3, ($4 == "" ? "(none)" : $4) }' /etc/group

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    pause_screen
}

# Displays currently logged-in users via who
# OS Concept: Session tracking via /var/run/utmp
show_logged_in_users() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                     CURRENTLY LOGGED-IN SESSIONS (utmp)                        %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%-15s %-12s %-20s %-20s\n" "USER" "TTY/LINE" "LOGIN TIME" "REMOTE HOST/IP"
    printf "%s\n" "--------------------------------------------------------------------------------"

    who 2>/dev/null | awk '{ printf "%-15s %-12s %-10s %-9s %-20s\n", $1, $2, $3, $4, ($5 == "" ? "localhost" : $5) }'

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    pause_screen
}

# Displays recent login history via last
# OS Concept: Historical user accounting via /var/log/wtmp
show_login_history() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                     HISTORICAL LOGIN SESSIONS (wtmp)                           %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    last -n 15 2>/dev/null || printf "Login accounting history unavailable.\n"

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    pause_screen
}

# Audits password aging and expiration policy for a user via chage
# OS Concept: Shadow password suite expiration and aging policies (/etc/shadow)
audit_password_aging() {
    printf "\nEnter username to inspect password aging: "
    read -r target_user

    if ! is_valid_username "${target_user}"; then
        printf "%s[ERROR] Invalid username format.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        sleep 1
        return 1
    fi

    if ! id "${target_user}" >/dev/null 2>&1; then
        printf "%s[ERROR] User '%s' does not exist on this system.%s\n" "${COLOR_RED}" "${target_user}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    clear
    printf "%s================ PASSWORD AGING POLICY: %s ================%s\n\n" "${COLOR_BOLD}${COLOR_CYAN}" "${target_user}" "${COLOR_RESET}"
    
    if is_root; then
        chage -l "${target_user}" 2>/dev/null
    else
        # If non-root, chage -l might work for self, or try sudo if permitted
        if [[ "${target_user}" == "${USER:-$(whoami)}" ]]; then
            chage -l "${target_user}" 2>/dev/null || true
        else
            printf "%s[NOTICE] Reading /etc/shadow password aging for other users requires superuser privileges.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
            printf "Attempting privileged query...\n"
            sudo -n chage -l "${target_user}" 2>/dev/null || printf "%s[PERMISSION DENIED] Please run NexAdmin as root or with sudo to inspect shadow policies.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        fi
    fi

    pause_screen
}

# ==============================================================================
# Administrative Operations (Modifying Users & Groups)
# OS Concept: System user provisioning, home directories, security groups
# ==============================================================================

# Adds a new local system user
add_system_user() {
    if ! require_root_or_warn "Creating new user accounts"; then
        pause_screen
        return 1
    fi

    printf "\nEnter new username: "
    read -r new_user

    if ! is_valid_username "${new_user}"; then
        printf "%s[ERROR] Invalid username! Must start with a letter/underscore and contain only lowercase letters, digits, '_' or '-'.%s\n" \
            "${COLOR_RED}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    if id "${new_user}" >/dev/null 2>&1; then
        printf "%s[ERROR] User '%s' already exists!%s\n" "${COLOR_RED}" "${new_user}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    if confirm "Create user '${new_user}' with standard home directory and bash shell?"; then
        if useradd -m -s /bin/bash "${new_user}" 2>/dev/null; then
            log_action "Created system user: ${new_user}"
            printf "%s[SUCCESS] User '%s' created successfully!%s\n" "${COLOR_GREEN}" "${new_user}" "${COLOR_RESET}"
            printf "Please set a password for the new user:\n"
            passwd "${new_user}"
        else
            printf "%s[ERROR] Failed to execute useradd for '%s'.%s\n" "${COLOR_RED}" "${new_user}" "${COLOR_RESET}"
        fi
    fi
    pause_screen
}

# Deletes an existing system user
delete_system_user() {
    if ! require_root_or_warn "Deleting user accounts"; then
        pause_screen
        return 1
    fi

    printf "\nEnter username to delete: "
    read -r del_user

    if ! is_valid_username "${del_user}"; then
        printf "%s[ERROR] Invalid username format.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    # Safety checks: Never delete root or currently active user
    if [[ "${del_user}" == "root" ]]; then
        printf "%s[CRITICAL REJECTION] Deleting the root administrator account is strictly prohibited!%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    if [[ "${del_user}" == "${USER:-$(whoami)}" ]]; then
        printf "%s[SAFETY REJECTION] Cannot delete the currently logged-in user (%s)!%s\n" "${COLOR_RED}" "${del_user}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    if ! id "${del_user}" >/dev/null 2>&1; then
        printf "%s[ERROR] User '%s' does not exist!%s\n" "${COLOR_RED}" "${del_user}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    if confirm "CONFIRM: Are you sure you want to permanently delete user '${del_user}'?" "n"; then
        local rm_home_flag=""
        if confirm "Also delete user's home directory and mail spool (-r)?" "n"; then
            rm_home_flag="-r"
        fi

        if userdel ${rm_home_flag} "${del_user}" 2>/dev/null; then
            log_action "Deleted user: ${del_user} (remove_home: ${rm_home_flag:-no})"
            printf "%s[SUCCESS] User '%s' deleted successfully.%s\n" "${COLOR_GREEN}" "${del_user}" "${COLOR_RESET}"
        else
            printf "%s[ERROR] userdel command failed. User may have active running processes.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        fi
    fi
    pause_screen
}

# Locks or unlocks a user account
toggle_user_lock() {
    local action="$1" # lock or unlock
    if ! require_root_or_warn "${action} user accounts"; then
        pause_screen
        return 1
    fi

    printf "\nEnter username to %s: " "${action}"
    read -r target_user

    if [[ "${target_user}" == "root" || "${target_user}" == "${USER:-$(whoami)}" ]]; then
        printf "%s[SAFETY REJECTION] Locking root or the active operator is prohibited.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    if ! id "${target_user}" >/dev/null 2>&1; then
        printf "%s[ERROR] User '%s' does not exist.%s\n" "${COLOR_RED}" "${target_user}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    if [[ "${action}" == "lock" ]]; then
        if usermod -L "${target_user}" 2>/dev/null; then
            log_action "Locked account: ${target_user}"
            printf "%s[SUCCESS] Account '%s' locked successfully (usermod -L).%s\n" "${COLOR_GREEN}" "${target_user}" "${COLOR_RESET}"
        fi
    else
        if usermod -U "${target_user}" 2>/dev/null; then
            log_action "Unlocked account: ${target_user}"
            printf "%s[SUCCESS] Account '%s' unlocked successfully (usermod -U).%s\n" "${COLOR_GREEN}" "${target_user}" "${COLOR_RESET}"
        fi
    fi
    pause_screen
}

# Adds a user to a supplementary group
add_user_to_group() {
    if ! require_root_or_warn "Modifying group memberships"; then
        pause_screen
        return 1
    fi

    printf "\nEnter target username: "
    read -r target_user
    printf "Enter supplementary group name to assign: "
    read -r group_name

    if ! id "${target_user}" >/dev/null 2>&1; then
        printf "%s[ERROR] User '%s' does not exist.%s\n" "${COLOR_RED}" "${target_user}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    if ! grep -q "^${group_name}:" /etc/group 2>/dev/null; then
        printf "%s[ERROR] Group '%s' does not exist.%s\n" "${COLOR_RED}" "${group_name}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    if usermod -aG "${group_name}" "${target_user}" 2>/dev/null; then
        log_action "Added user ${target_user} to supplementary group ${group_name}"
        printf "%s[SUCCESS] User '%s' added to group '%s' (usermod -aG).%s\n" "${COLOR_GREEN}" "${target_user}" "${group_name}" "${COLOR_RESET}"
    else
        printf "%s[ERROR] Failed to add user to group.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
    fi
    pause_screen
}

# ==============================================================================
# User Management Interactive Menu
# ==============================================================================
menu_user_management() {
    log_action "Accessed User Management"
    local u_choice=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                    NEXADMIN - USER & GROUP ADMINISTRATION                      %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        
        local priv_status
        if is_root; then
            priv_status="${COLOR_GREEN}Superuser (Root)${COLOR_RESET}"
        else
            priv_status="${COLOR_YELLOW}Read-Only / Unprivileged User (${USER:-$(whoami)})${COLOR_RESET}"
        fi
        printf " Operator Role: %s\n" "${priv_status}"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "  %s[Read-Only Telemetry & Auditing]%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  1) List Standard Users (UID >= 1000)\n"
        printf "  2) List System Groups (GID >= 1000)\n"
        printf "  3) Show Currently Logged-in Sessions (who)\n"
        printf "  4) Show Historical Login Sessions (last)\n"
        printf "  5) Audit User Password Aging Policy (chage)\n"
        printf "\n  %s[Administrative Actions (Requires Root / Sudo)]%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        printf "  6) Add New System User\n"
        printf "  7) Delete System User\n"
        printf "  8) Lock User Account\n"
        printf "  9) Unlock User Account\n"
        printf " 10) Add User to Supplementary Group\n"
        printf "  0) Back to Main Menu\n"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-10]: "
        read -r u_choice

        case "${u_choice}" in
            1) list_regular_users ;;
            2) list_system_groups ;;
            3) show_logged_in_users ;;
            4) show_login_history ;;
            5) audit_password_aging ;;
            6) add_system_user ;;
            7) delete_system_user ;;
            8) toggle_user_lock "lock" ;;
            9) toggle_user_lock "unlock" ;;
            10) add_user_to_group ;;
            0) break ;;
            *)
                printf "%sInvalid choice! Choose 0-10.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}
