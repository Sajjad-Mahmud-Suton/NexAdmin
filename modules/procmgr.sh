#!/usr/bin/env bash
# ==============================================================================
# File: modules/procmgr.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: Process Control & Lifecycle Management. Supports signal dispatching
#          (SIGTERM, SIGKILL, SIGSTOP, SIGCONT), dynamic priority adjustment (renice),
#          zombie process auditing, uninterruptible sleep (D-state) diagnostics,
#          and background job inspection.
# ==============================================================================

# ==============================================================================
# Safety Checks for Process Management
# OS Concept: Process isolation and OS stability protection
# ==============================================================================
is_protected_pid() {
    local target_pid="$1"

    # PID 1: init/systemd (system crash if killed)
    if [[ "${target_pid}" -eq 1 ]]; then
        printf "%s[SAFETY VIOLATION] PID 1 is the system init daemon! Operation aborted to prevent kernel panic.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        return 0
    fi

    # NexAdmin's current shell process
    if [[ "${target_pid}" -eq "$$" ]]; then
        printf "%s[SAFETY VIOLATION] Target PID matches NexAdmin script PID ($$)! Operation aborted.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        return 0
    fi

    # NexAdmin's parent process
    if [[ "${target_pid}" -eq "${PPID}" ]]; then
        printf "%s[SAFETY VIOLATION] Target PID matches NexAdmin parent shell (PPID: ${PPID})! Operation aborted.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        return 0
    fi

    return 1
}

# ==============================================================================
# Signal Transmission & Error Handling
# OS Concept: UNIX IPC Signals (kill syscall) and errno handling (EPERM / ESRCH)
# ==============================================================================
send_signal_to_process() {
    local target_pid="$1"
    local sig_name="$2"
    local sig_num="$3"

    if ! is_number "${target_pid}"; then
        printf "%s[ERROR] Invalid PID: Must be a positive integer.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        return 1
    fi

    if ! is_pid "${target_pid}"; then
        printf "%s[ERROR] Process with PID %s does not exist or has already terminated.%s\n" "${COLOR_RED}" "${target_pid}" "${COLOR_RESET}"
        return 1
    fi

    if is_protected_pid "${target_pid}"; then
        return 1
    fi

    local proc_name
    proc_name="$(ps -p "${target_pid}" -o comm= 2>/dev/null || echo "unknown")"

    # Execute signal dispatch
    local kill_output
    if kill_output="$(kill -"${sig_num}" "${target_pid}" 2>&1)"; then
        log_action "Dispatched signal ${sig_name} (${sig_num}) to PID ${target_pid} [${proc_name}]"
        printf "%s[SUCCESS] Successfully sent %s (%s) to PID %s (%s).%s\n" \
            "${COLOR_GREEN}" "${sig_name}" "${sig_num}" "${target_pid}" "${proc_name}" "${COLOR_RESET}"
        return 0
    else
        log_action "FAILED to send signal ${sig_name} to PID ${target_pid}: ${kill_output}"
        if [[ "${kill_output}" =~ "Operation not permitted" ]]; then
            printf "%s[PERMISSION DENIED] Operation not permitted for PID %s (%s).%s\n" "${COLOR_RED}" "${target_pid}" "${proc_name}" "${COLOR_RESET}"
            printf "%sReason: Process belongs to another user or root. Please re-run NexAdmin with 'sudo' to manage this process.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        else
            printf "%s[ERROR] Failed to send signal: %s%s\n" "${COLOR_RED}" "${kill_output}" "${COLOR_RESET}"
        fi
        return 1
    fi
}

# ==============================================================================
# Priority Adjustment (renice)
# OS Concept: Process scheduling nice value (-20 highest priority to 19 lowest)
# ==============================================================================
change_process_priority() {
    local target_pid="$1"

    if ! is_number "${target_pid}"; then
        printf "%s[ERROR] Invalid PID.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        return 1
    fi

    if ! is_pid "${target_pid}"; then
        printf "%s[ERROR] Process %s does not exist.%s\n" "${COLOR_RED}" "${target_pid}" "${COLOR_RESET}"
        return 1
    fi

    local current_nice
    current_nice="$(ps -p "${target_pid}" -o ni= 2>/dev/null | tr -d ' ')"
    printf "Current nice value for PID %s: %s%s%s (Range: -20 to 19)\n" "${target_pid}" "${COLOR_BOLD}" "${current_nice}" "${COLOR_RESET}"
    printf "Enter new nice value (-20 to 19): "
    read -r new_nice

    # Validate integer within range
    if ! [[ "${new_nice}" =~ ^-?[0-9]+$ ]] || (( new_nice < -20 || new_nice > 19 )); then
        printf "%s[ERROR] Nice value must be an integer between -20 and 19.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        return 1
    fi

    # Negative nice values (higher priority) strictly require superuser
    if (( new_nice < current_nice )) && ! is_root; then
        require_root_or_warn "Decreasing nice value (raising CPU scheduling priority)"
    fi

    local renice_output
    if renice_output="$(renice -n "${new_nice}" -p "${target_pid}" 2>&1)"; then
        log_action "Adjusted nice priority for PID ${target_pid} to ${new_nice}"
        printf "%s[SUCCESS] %s%s\n" "${COLOR_GREEN}" "${renice_output}" "${COLOR_RESET}"
    else
        log_action "FAILED to renice PID ${target_pid}: ${renice_output}"
        if [[ "${renice_output}" =~ "Operation not permitted" ]]; then
            printf "%s[PERMISSION DENIED] Cannot change priority of PID %s.%s\n" "${COLOR_RED}" "${target_pid}" "${COLOR_RESET}"
            printf "%sOnly root can set negative nice values or alter processes owned by other users.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        else
            printf "%s[ERROR] %s%s\n" "${COLOR_RED}" "${renice_output}" "${COLOR_RESET}"
        fi
    fi
}

# ==============================================================================
# Zombie Process Auditor
# OS Concept: A Zombie (defunct) process has completed execution via exit(),
#             but its task_struct remains until its parent executes wait().
#             Zombies CANNOT be killed with signals (they are already dead);
#             the parent process must be reaped or terminated.
# ==============================================================================
audit_zombie_processes() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                        ZOMBIE (DEFUNCT) PROCESS AUDITOR                        %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    local zombies
    zombies="$(ps -eo pid,ppid,user,stat,comm 2>/dev/null | awk '$4 ~ /^Z/ {print $1, $2, $3, $5}')"

    if [[ -z "${zombies}" ]]; then
        printf "%s[OK] No zombie processes detected on the system.%s\n\n" "${COLOR_GREEN}" "${COLOR_RESET}"
    else
        printf "%s[WARNING] Detected defunct zombie processes:%s\n\n" "${COLOR_RED}" "${COLOR_RESET}"
        printf "%-8s %-8s %-12s %-25s\n" "Z_PID" "PPID" "USER" "COMMAND"
        printf "%s\n" "--------------------------------------------------------------------------------"
        echo "${zombies}" | while read -r z_pid ppid usr comm; do
            local parent_name
            parent_name="$(ps -p "${ppid}" -o comm= 2>/dev/null || echo "terminated")"
            printf "%-8s %-8s %-12s %-25s\n" "${z_pid}" "${ppid}" "${usr}" "${comm} (Parent: ${parent_name})"
        done

        printf "\n%s[OPERATING SYSTEM THEORY NOTE]%s\n" "${COLOR_BOLD}${COLOR_YELLOW}" "${COLOR_RESET}"
        printf "A zombie process has already finished executing and holds NO memory or CPU.\n"
        printf "It cannot be killed with SIGKILL (signal 9) because it is already dead!\n"
        printf "To eliminate a zombie, its PARENT process (PPID) must invoke the 'wait()' syscall.\n"
        printf "If the parent is frozen, terminating the parent process will cause the init/systemd\n"
        printf "daemon (PID 1) to adopt the zombie and immediately reap its entry from the process table.\n"
    fi
    pause_screen
}

# ==============================================================================
# Unresponsive (D-State) Process Inspector
# OS Concept: State D = Uninterruptible Sleep. Process is waiting inside kernel
#             for I/O (disk, NFS, hardware driver) and will NOT respond to signals.
# ==============================================================================
audit_dstate_processes() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                UNINTERRUPTIBLE SLEEP (D-STATE) PROCESS AUDITOR                 %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    local d_procs
    d_procs="$(ps -eo pid,user,time,wchan:20,comm 2>/dev/null | awk '$4 ~ /^D/ || $0 ~ / D / {print $0}')"

    if [[ -z "${d_procs}" ]]; then
        printf "%s[OK] No unresponsive (D-State) processes detected.%s\n\n" "${COLOR_GREEN}" "${COLOR_RESET}"
    else
        printf "%s[WARNING] Processes currently in Uninterruptible Sleep (D State):%s\n\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        ps -eo pid,user,stat,wchan:20,comm 2>/dev/null | grep -E '^ +[0-9]+ +[^ ]+ +D' || echo "${d_procs}"

        printf "\n%s[OPERATING SYSTEM THEORY NOTE]%s\n" "${COLOR_BOLD}${COLOR_YELLOW}" "${COLOR_RESET}"
        printf "Processes in State 'D' are waiting in kernel space for hardware or filesystem I/O.\n"
        printf "They cannot be terminated even with SIGKILL until the waiting I/O completes or times out.\n"
    fi
    pause_screen
}

# ==============================================================================
# Background Jobs Inspector
# OS Concept: Process groups, session leaders, and job control
# ==============================================================================
list_user_background_jobs() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                   ACTIVE USER BACKGROUND PROCESSES & SESSIONS                  %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    local current_user="${USER:-$(whoami)}"
    printf "Processes owned by %s%s%s running in background (TTY '?'):\n\n" "${COLOR_BOLD}" "${current_user}" "${COLOR_RESET}"
    printf "%-8s %-6s %-6s %-10s %-8s %-25s\n" "PID" "%CPU" "%MEM" "ELAPSED" "STATE" "COMMAND"
    printf "%s\n" "--------------------------------------------------------------------------------"

    ps -u "${current_user}" -o pid,%cpu,%mem,etime,stat,tty,comm 2>/dev/null | awk '$6 == "?" { printf "%-8s %-6s %-6s %-10s %-8s %-25s\n", $1, $2, $3, $4, $5, $7 }' | head -n 30

    pause_screen
}

# ==============================================================================
# Process Manager Interactive Menu
# ==============================================================================
menu_process_manager() {
    log_action "Opened Process Manager"
    local mgr_choice=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                 NEXADMIN - PROCESS CONTROL & LIFECYCLE MANAGER                 %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  1) Terminate Process Gracefully (SIGTERM - 15)\n"
        printf "  2) Force Kill Process Immediately (SIGKILL - 9) [FORCE]\n"
        printf "  3) Pause / Suspend Process Execution (SIGSTOP - 19)\n"
        printf "  4) Resume Suspended Process (SIGCONT - 18)\n"
        printf "  5) Change Process Priority / Niceness (renice)\n"
        printf "  6) Audit Zombie (Defunct) Processes\n"
        printf "  7) Audit Unresponsive (D-State) Processes\n"
        printf "  8) List Background User Processes\n"
        printf "  0) Back to Main Menu\n"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-8]: "
        read -r mgr_choice

        case "${mgr_choice}" in
            1)
                printf "\nEnter PID to terminate gracefully (SIGTERM): "
                read -r t_pid
                if ! is_pid "${t_pid}"; then
                    printf "%s[ERROR] Process %s does not exist.%s\n" "${COLOR_RED}" "${t_pid}" "${COLOR_RESET}"
                    sleep 1
                    continue
                fi
                local p_name
                p_name="$(ps -p "${t_pid}" -o comm= 2>/dev/null)"
                if confirm "Are you sure you want to send SIGTERM to PID ${t_pid} (${p_name})?"; then
                    send_signal_to_process "${t_pid}" "SIGTERM" 15
                fi
                pause_screen
                ;;
            2)
                printf "\nEnter PID to FORCE KILL immediately (SIGKILL): "
                read -r t_pid
                if ! is_pid "${t_pid}"; then
                    printf "%s[ERROR] Process %s does not exist.%s\n" "${COLOR_RED}" "${t_pid}" "${COLOR_RESET}"
                    sleep 1
                    continue
                fi
                local p_name
                p_name="$(ps -p "${t_pid}" -o comm= 2>/dev/null)"
                printf "%s[WARNING] SIGKILL (Signal 9) cannot be caught or ignored. Process will terminate instantly without cleanup!%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                if confirm "CONFIRM FORCE KILL for PID ${t_pid} (${p_name})?"; then
                    send_signal_to_process "${t_pid}" "SIGKILL" 9
                fi
                pause_screen
                ;;
            3)
                printf "\nEnter PID to suspend/pause (SIGSTOP): "
                read -r t_pid
                if confirm "Pause execution of PID ${t_pid}?"; then
                    send_signal_to_process "${t_pid}" "SIGSTOP" 19
                fi
                pause_screen
                ;;
            4)
                printf "\nEnter PID to resume (SIGCONT): "
                read -r t_pid
                if confirm "Resume execution of PID ${t_pid}?"; then
                    send_signal_to_process "${t_pid}" "SIGCONT" 18
                fi
                pause_screen
                ;;
            5)
                printf "\nEnter PID to adjust priority: "
                read -r t_pid
                change_process_priority "${t_pid}"
                pause_screen
                ;;
            6)
                audit_zombie_processes
                ;;
            7)
                audit_dstate_processes
                ;;
            8)
                list_user_background_jobs
                ;;
            0)
                break
                ;;
            *)
                printf "%sInvalid choice! Please choose 0-8.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}
