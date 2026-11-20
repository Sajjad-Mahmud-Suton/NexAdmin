#!/usr/bin/env bash
# ==============================================================================
# File: modules/process.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: Process Telemetry & Inspection. Provides process listing, top resource
#          consumers, pattern search, and in-depth process hierarchy tree inspection.
# ==============================================================================

# Translates single-letter Linux process state codes into readable descriptions
# OS Concept: Process State Lifecycle in Linux (Task States)
describe_process_state() {
    local raw_state="$1"
    case "${raw_state:0:1}" in
        R) echo "Running" ;;
        S) echo "Sleeping (Interruptible)" ;;
        D) echo "Disk Sleep (Uninterruptible)" ;;
        T) echo "Stopped / Traced" ;;
        t) echo "Tracing Stop" ;;
        Z) echo "Zombie (Defunct)" ;;
        X) echo "Dead" ;;
        I) echo "Idle Kernel Thread" ;;
        *) echo "Unknown (${raw_state})" ;;
    esac
}

# ==============================================================================
# 1. Process List Display
# OS Concept: Process table query via ps and /proc
# ==============================================================================
menu_process_list() {
    log_action "Viewed Process List"
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                        NEXADMIN - RUNNING PROCESS TABLE                        %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    
    # State count summary banner
    local total_cnt run_cnt sleep_cnt d_cnt stop_cnt zombie_cnt
    total_cnt="$(ps -e --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    run_cnt="$(ps -eo stat= 2>/dev/null | grep -c '^R' || true)"
    sleep_cnt="$(ps -eo stat= 2>/dev/null | grep -c '^S' || true)"
    d_cnt="$(ps -eo stat= 2>/dev/null | grep -c '^D' || true)"
    stop_cnt="$(ps -eo stat= 2>/dev/null | grep -c '^T' || true)"
    zombie_cnt="$(ps -eo stat= 2>/dev/null | grep -c '^Z' || true)"

    printf " Summary: %sTotal:%s %s | %sRunning:%s %s | %sSleeping:%s %s | %sDiskSleep:%s %s | %sStopped:%s %s | %sZombie:%s %s\n" \
        "${COLOR_BOLD}" "${COLOR_RESET}" "${total_cnt}" \
        "${COLOR_GREEN}" "${COLOR_RESET}" "${run_cnt}" \
        "${COLOR_CYAN}" "${COLOR_RESET}" "${sleep_cnt}" \
        "${COLOR_YELLOW}" "${COLOR_RESET}" "${d_cnt}" \
        "${COLOR_MAGENTA}" "${COLOR_RESET}" "${stop_cnt}" \
        "${COLOR_RED}" "${COLOR_RESET}" "${zombie_cnt}"
    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"

    # Print Table Headers
    printf "%-8s %-12s %-6s %-6s %-10s %-12s %-20s\n" "PID" "USER" "%CPU" "%MEM" "TIME" "STATE" "COMMAND"
    printf "%s\n" "--------------------------------------------------------------------------------"

    # Display Top 25 processes sorted by CPU usage
    ps -eo pid,user,%cpu,%mem,time,stat,comm --sort=-%cpu 2>/dev/null | tail -n +2 | head -n 25 | while read -r pid usr cpu mem time stat comm; do
        local state_desc
        state_desc="$(describe_process_state "${stat}")"
        # Truncate state description for compact table display
        state_desc="${state_desc:0:11}"
        printf "%-8s %-12s %-6s %-6s %-10s %-12s %-20s\n" "${pid}" "${usr:0:11}" "${cpu}" "${mem}" "${time}" "${state_desc}" "${comm:0:20}"
    done

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    printf "Displaying top 25 active processes. Use Option 4 for specific PID search.\n"
    pause_screen
}

# ==============================================================================
# 2. Top 10 CPU and RAM Processes
# OS Concept: Resource utilization sorting and scheduling metrics
# ==============================================================================
menu_top_processes() {
    log_action "Viewed Top 10 CPU/RAM Processes"
    local sub_choice=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                       TOP RESOURCE-CONSUMING PROCESSES                         %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  1) Top 10 Processes by CPU Usage\n"
        printf "  2) Top 10 Processes by Memory Usage (RAM)\n"
        printf "  3) Combined Overview (Side-by-Side Summary)\n"
        printf "  0) Back to Main Menu\n"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-3]: "
        read -r sub_choice

        case "${sub_choice}" in
            1)
                clear
                printf "%s==================== TOP 10 PROCESSES BY CPU USAGE ====================%s\n\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
                printf "%-8s %-12s %-8s %-8s %-10s %-25s\n" "PID" "USER" "%CPU" "%MEM" "ELAPSED" "COMMAND"
                printf "%s\n" "--------------------------------------------------------------------------------"
                ps -eo pid,user,%cpu,%mem,etime,comm --sort=-%cpu 2>/dev/null | tail -n +2 | head -n 10 | while read -r pid usr cpu mem etime comm; do
                    printf "%-8s %-12s %-8s %-8s %-10s %-25s\n" "${pid}" "${usr:0:11}" "${cpu}%" "${mem}%" "${etime}" "${comm:0:25}"
                done
                pause_screen
                ;;
            2)
                clear
                printf "%s=================== TOP 10 PROCESSES BY MEMORY USAGE ==================%s\n\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
                printf "%-8s %-12s %-8s %-8s %-10s %-25s\n" "PID" "USER" "%MEM" "%CPU" "ELAPSED" "COMMAND"
                printf "%s\n" "--------------------------------------------------------------------------------"
                ps -eo pid,user,%mem,%cpu,etime,comm --sort=-%mem 2>/dev/null | tail -n +2 | head -n 10 | while read -r pid usr mem cpu etime comm; do
                    printf "%-8s %-12s %-8s %-8s %-10s %-25s\n" "${pid}" "${usr:0:11}" "${mem}%" "${cpu}%" "${etime}" "${comm:0:25}"
                done
                pause_screen
                ;;
            3)
                clear
                printf "%s==================== TOP 5 CPU & TOP 5 MEMORY OVERVIEW ====================%s\n\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
                printf "%s--- TOP 5 CPU CONSUMERS ---%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
                printf "%-8s %-12s %-8s %-8s %-25s\n" "PID" "USER" "%CPU" "%MEM" "COMMAND"
                ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | tail -n +2 | head -n 5 | while read -r pid usr cpu mem comm; do
                    printf "%-8s %-12s %-8s %-8s %-25s\n" "${pid}" "${usr:0:11}" "${cpu}%" "${mem}%" "${comm:0:25}"
                done
                printf "\n%s--- TOP 5 MEMORY CONSUMERS ---%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
                printf "%-8s %-12s %-8s %-8s %-25s\n" "PID" "USER" "%MEM" "%CPU" "COMMAND"
                ps -eo pid,user,%mem,%cpu,comm --sort=-%mem 2>/dev/null | tail -n +2 | head -n 5 | while read -r pid usr mem cpu comm; do
                    printf "%-8s %-12s %-8s %-8s %-25s\n" "${pid}" "${usr:0:11}" "${mem}%" "${cpu}%" "${comm:0:25}"
                done
                pause_screen
                ;;
            0)
                break
                ;;
            *)
                printf "%sInvalid selection! Please enter 0-3.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# 3. Search Process and In-Depth Process Inspector
# OS Concept: /proc virtual filesystem inspection, process hierarchy tree (parent/child)
# ==============================================================================

# Displays comprehensive details for a given PID from /proc and ps
show_pid_details() {
    local target_pid="$1"

    # Validate target process exists
    if ! is_pid "${target_pid}"; then
        printf "%s[ERROR] Process with PID %s does not exist or has already terminated.%s\n" "${COLOR_RED}" "${target_pid}" "${COLOR_RESET}"
        return 1
    fi

    local proc_dir="/proc/${target_pid}"
    if [[ ! -r "${proc_dir}/status" ]]; then
        printf "%s[ERROR] Unable to read %s/status (insufficient permissions or process terminated).%s\n" "${COLOR_RED}" "${proc_dir}" "${COLOR_RESET}"
        return 1
    fi

    # Read values defensively
    local proc_name ppid_val proc_state threads_cnt vmrss_val vmsize_val
    proc_name="$(grep '^Name:' "${proc_dir}/status" 2>/dev/null | awk '{print $2}')"
    ppid_val="$(grep '^PPid:' "${proc_dir}/status" 2>/dev/null | awk '{print $2}')"
    proc_state="$(grep '^State:' "${proc_dir}/status" 2>/dev/null | cut -d: -f2- | sed -e 's/^[[:space:]]*//')"
    threads_cnt="$(grep '^Threads:' "${proc_dir}/status" 2>/dev/null | awk '{print $2}')"
    vmrss_val="$(grep '^VmRSS:' "${proc_dir}/status" 2>/dev/null | awk '{print $2, $3}')"
    vmsize_val="$(grep '^VmSize:' "${proc_dir}/status" 2>/dev/null | awk '{print $2, $3}')"

    [[ -z "${vmrss_val}" ]] && vmrss_val="0 kB (Kernel Worker / Shared)"
    [[ -z "${vmsize_val}" ]] && vmsize_val="0 kB"

    # PS queries for user, cpu, mem, start time
    local proc_user proc_cpu proc_mem proc_etime proc_start
    proc_user="$(ps -p "${target_pid}" -o user= 2>/dev/null | tr -d ' ')"
    proc_cpu="$(ps -p "${target_pid}" -o %cpu= 2>/dev/null | tr -d ' ')"
    proc_mem="$(ps -p "${target_pid}" -o %mem= 2>/dev/null | tr -d ' ')"
    proc_etime="$(ps -p "${target_pid}" -o etime= 2>/dev/null | tr -d ' ')"
    proc_start="$(ps -p "${target_pid}" -o lstart= 2>/dev/null | sed -e 's/^[[:space:]]*//')"

    # Command line from /proc/PID/cmdline (null-byte separated)
    local full_cmd
    full_cmd="$(tr '\0' ' ' < "${proc_dir}/cmdline" 2>/dev/null)"
    [[ -z "${full_cmd}" ]] && full_cmd="[${proc_name}]"

    printf "\n%s==================== PROCESS DETAILS: PID %s ====================%s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${target_pid}" "${COLOR_RESET}"
    printf " Process Name       : %s%s%s\n" "${COLOR_BOLD}" "${proc_name}" "${COLOR_RESET}"
    printf " Process ID (PID)   : %s\n" "${target_pid}"
    printf " Parent PID (PPID)  : %s\n" "${ppid_val}"
    printf " Owner / User       : %s\n" "${proc_user}"
    printf " State              : %s%s%s\n" "${COLOR_YELLOW}" "${proc_state}" "${COLOR_RESET}"
    printf " Active Threads     : %s\n" "${threads_cnt}"
    printf " CPU Utilization    : %s%%\n" "${proc_cpu}"
    printf " Memory Utilization : %s%%\n" "${proc_mem}"
    printf " Resident RAM (RSS) : %s\n" "${vmrss_val}"
    printf " Virtual Size (VSZ) : %s\n" "${vmsize_val}"
    printf " Start Time         : %s\n" "${proc_start}"
    printf " Elapsed Run Time   : %s\n" "${proc_etime}"
    printf " Executable Command : %s\n" "${full_cmd}"

    # Parent Process Details
    printf "\n%s--- PARENT PROCESS HIERARCHY ---%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
    if [[ -n "${ppid_val}" && "${ppid_val}" -gt 0 ]]; then
        if is_pid "${ppid_val}"; then
            local parent_cmd
            parent_cmd="$(ps -p "${ppid_val}" -o comm= 2>/dev/null)"
            printf " Parent PID %s (%s)\n" "${ppid_val}" "${parent_cmd}"
        else
            printf " Parent PID %s (Terminated / Reaped by Init)\n" "${ppid_val}"
        fi
    else
        printf " None (Top-level Root Process)\n"
    fi

    # Child Processes Listing
    printf "\n%s--- CHILD PROCESSES ---%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
    local children
    children="$(pgrep -P "${target_pid}" 2>/dev/null || true)"
    if [[ -n "${children}" ]]; then
        printf "%-8s %-12s %-25s\n" "PID" "USER" "COMMAND"
        for cpid in ${children}; do
            ps -p "${cpid}" -o pid=,user=,comm= 2>/dev/null | while read -r p u c; do
                printf "%-8s %-12s %-25s\n" "${p}" "${u}" "${c}"
            done
        done
    else
        printf " No active child processes.\n"
    fi
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
}

menu_search_process() {
    log_action "Accessed Search Process / Process Details"
    local search_choice=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                     SEARCH PROCESS & INSPECT HIERARCHY                         %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  1) Search Processes by Keyword / Name\n"
        printf "  2) Inspect In-Depth Details by PID\n"
        printf "  3) View Process Counts Breakdown by User\n"
        printf "  0) Back to Main Menu\n"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-3]: "
        read -r search_choice

        case "${search_choice}" in
            1)
                printf "\nEnter process name or keyword to search: "
                read -r keyword
                keyword="$(echo "${keyword}" | tr -cd 'A-Za-z0-9_.-')"
                if [[ -z "${keyword}" ]]; then
                    printf "%sKeyword cannot be empty.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1
                    continue
                fi

                printf "\n%sSearch results matching '%s':%s\n" "${COLOR_BOLD}" "${keyword}" "${COLOR_RESET}"
                printf "%-8s %-12s %-6s %-6s %-8s %-25s\n" "PID" "USER" "%CPU" "%MEM" "STATE" "COMMAND"
                printf "%s\n" "--------------------------------------------------------------------------------"

                local matches
                matches="$(ps -eo pid,user,%cpu,%mem,stat,comm 2>/dev/null | tail -n +2 | grep -i "${keyword}" || true)"
                if [[ -n "${matches}" ]]; then
                    echo "${matches}" | while read -r p u c m s cmd; do
                        printf "%-8s %-12s %-6s %-6s %-8s %-25s\n" "${p}" "${u:0:11}" "${c}" "${m}" "${s:0:6}" "${cmd:0:25}"
                    done
                else
                    printf "No processes matching '%s' were found.\n" "${keyword}"
                fi
                pause_screen
                ;;
            2)
                printf "\nEnter Process ID (PID) to inspect: "
                read -r target_pid
                if ! is_number "${target_pid}"; then
                    printf "%s[ERROR] Invalid PID: Must be a positive integer.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                    sleep 1.2
                    continue
                fi
                show_pid_details "${target_pid}"
                pause_screen
                ;;
            3)
                clear
                printf "%s================ PROCESS BREAKDOWN BY SYSTEM USER ================%s\n\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
                printf "%-20s %-15s\n" "SYSTEM USER" "ACTIVE PROCESSES"
                printf "%s\n" "------------------------------------"
                ps -eo user= 2>/dev/null | sort | uniq -c | sort -nr | while read -r cnt user; do
                    printf "%-20s %-15s\n" "${user}" "${cnt}"
                done
                pause_screen
                ;;
            0)
                break
                ;;
            *)
                printf "%sInvalid selection! Please enter 0-3.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}
