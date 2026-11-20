#!/usr/bin/env bash
# ==============================================================================
# File: modules/network.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: Network Diagnostics & Socket Inspector. Visualizes interface configs,
#          default routes, DNS resolvers, active listening sockets, ICMP reachability,
#          and real-time network interface bandwidth metrics via /proc/net/dev.
# ==============================================================================

# ==============================================================================
# 1. IP Configuration & Interface Listing
# OS Concept: Linux network namespaces and netlink interface queries (iproute2)
# ==============================================================================
show_ip_configurations() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                        NETWORK INTERFACE CONFIGURATIONS                        %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    if has_cmd ip; then
        printf "%-12s %-8s %-40s\n" "INTERFACE" "STATE" "IP ADDRESSES"
        printf "%s\n" "--------------------------------------------------------------------------------"
        ip -brief addr 2>/dev/null | while read -r iface state addrs; do
            printf "%-12s %-8s %-40s\n" "${iface}" "${state}" "${addrs}"
        done
    else
        ifconfig -a 2>/dev/null || printf "Command 'ip' or 'ifconfig' not available.\n"
    fi

    # Default Gateway Routing
    printf "\n%s--- DEFAULT ROUTING GATEWAY ---%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    local default_gw
    default_gw="$(ip route show default 2>/dev/null || true)"
    if [[ -n "${default_gw}" ]]; then
        printf "Default Route: %s%s%s\n" "${COLOR_BOLD}" "${default_gw}" "${COLOR_RESET}"
    else
        printf "No default gateway configured.\n"
    fi

    # DNS Nameservers from /etc/resolv.conf
    printf "\n%s--- CONFIGURED DNS NAMESERVERS (/etc/resolv.conf) ---%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    local dns_servers
    dns_servers="$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' || true)"
    if [[ -n "${dns_servers}" ]]; then
        for ns in ${dns_servers}; do
            printf " - %s\n" "${ns}"
        done
    else
        printf "No DNS nameservers found in /etc/resolv.conf\n"
    fi

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    pause_screen
}

# ==============================================================================
# 2. Listening Sockets & Ports (ss -tuln)
# OS Concept: Transport layer endpoint bindings (TCP/UDP socket table in kernel)
# ==============================================================================
show_listening_ports() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                      ACTIVE LISTENING PORTS & SOCKETS                         %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    if has_cmd ss; then
        printf "%-8s %-10s %-25s %-20s\n" "PROTO" "STATE" "LOCAL ADDRESS:PORT" "PEER ADDRESS:PORT"
        printf "%s\n" "--------------------------------------------------------------------------------"
        ss -tuln 2>/dev/null | tail -n +2 | head -n 35 | while read -r proto state recvq sendq local peer; do
            printf "%-8s %-10s %-25s %-20s\n" "${proto}" "${state}" "${local}" "${peer}"
        done
    else
        netstat -tuln 2>/dev/null || printf "Command 'ss' or 'netstat' not found.\n"
    fi

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    pause_screen
}

# ==============================================================================
# 3. ICMP Ping Reachability Diagnostic
# OS Concept: ICMP Echo Request/Reply protocol and round-trip latency evaluation
# ==============================================================================
run_ping_diagnostic() {
    printf "\nEnter remote hostname or IP address to ping [default: 8.8.8.8]: "
    read -r target
    target="${target:-8.8.8.8}"

    # Sanitize hostname / IP
    target="$(echo "${target}" | tr -cd 'A-Za-z0-9_.-')"
    if [[ -z "${target}" ]]; then
        printf "%s[ERROR] Invalid host address.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        sleep 1
        return 1
    fi

    printf "\nTransmitting 3 ICMP echo packets to %s%s%s (2s timeout)...\n\n" "${COLOR_BOLD}" "${target}" "${COLOR_RESET}"
    local ping_result
    ping_result="$(ping -c 3 -W 2 "${target}" 2>&1)"

    echo "${ping_result}"

    if [[ "${ping_result}" =~ "0% packet loss" ]]; then
        printf "\n%s[CONNECTIVITY OK] Host %s is reachable with 0%% packet loss.%s\n" "${COLOR_GREEN}" "${target}" "${COLOR_RESET}"
    elif [[ "${ping_result}" =~ "100% packet loss" ]]; then
        printf "\n%s[CONNECTIVITY FAILED] Host %s is unreachable (100%% packet loss).%s\n" "${COLOR_RED}" "${target}" "${COLOR_RESET}"
    else
        printf "\n%s[WARNING] Partial packet loss or network jitter detected.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
    fi

    pause_screen
}

# ==============================================================================
# 4. Real-Time Network Bandwidth & I/O Speed
# OS Concept: Kernel network device packet counters in /proc/net/dev
# ==============================================================================
show_bandwidth_speed() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                  REAL-TIME NETWORK INTERFACE I/O & BANDWIDTH                   %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "Measuring transfer rate across interfaces (sampling 1 second)...\n\n"

    # Reading 1
    local net1 net2
    net1="$(grep ':' /proc/net/dev | grep -v 'lo:' 2>/dev/null || true)"
    sleep 1
    # Reading 2
    net2="$(grep ':' /proc/net/dev | grep -v 'lo:' 2>/dev/null || true)"

    if [[ -z "${net1}" || -z "${net2}" ]]; then
        printf "No physical network interfaces found.\n"
        pause_screen
        return 0
    fi

    printf "%-15s %-15s %-15s %-15s %-15s\n" "INTERFACE" "DOWNLOAD (KB/s)" "UPLOAD (KB/s)" "TOTAL RX (MB)" "TOTAL TX (MB)"
    printf "%s\n" "--------------------------------------------------------------------------------"

    # Compute delta per interface
    while read -r line1; do
        [[ -z "${line1}" ]] && continue
        local iface rx1 tx1
        iface="$(echo "${line1}" | cut -d: -f1 | tr -d ' ')"
        rx1="$(echo "${line1}" | cut -d: -f2 | awk '{print $1}')"
        tx1="$(echo "${line1}" | cut -d: -f2 | awk '{print $9}')"

        local line2 rx2 tx2
        line2="$(echo "${net2}" | grep "^ *${iface}:")"
        if [[ -n "${line2}" ]]; then
            rx2="$(echo "${line2}" | cut -d: -f2 | awk '{print $1}')"
            tx2="$(echo "${line2}" | cut -d: -f2 | awk '{print $9}')"

            local rx_diff=$(( rx2 - rx1 ))
            local tx_diff=$(( tx2 - tx1 ))

            local rx_rate_kb
            rx_rate_kb="$(awk -v d="${rx_diff}" 'BEGIN { printf "%.2f", d / 1024.0 }')"
            local tx_rate_kb
            tx_rate_kb="$(awk -v d="${tx_diff}" 'BEGIN { printf "%.2f", d / 1024.0 }')"

            local total_rx_mb
            total_rx_mb="$(awk -v r="${rx2}" 'BEGIN { printf "%.1f", r / (1024.0 * 1024.0) }')"
            local total_tx_mb
            total_tx_mb="$(awk -v t="${tx2}" 'BEGIN { printf "%.1f", t / (1024.0 * 1024.0) }')"

            printf "%-15s %-15s %-15s %-15s %-15s\n" "${iface}" "${rx_rate_kb}" "${tx_rate_kb}" "${total_rx_mb}" "${total_tx_mb}"
        fi
    done <<< "${net1}"

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    pause_screen
}

# ==============================================================================
# Network Info Interactive Menu
# ==============================================================================
menu_network_info() {
    log_action "Accessed Network Info"
    local net_choice=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                   NEXADMIN - NETWORK & SOCKET DIAGNOSTICS                      %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "  1) Display IP Configurations, Gateways & DNS Resolvers\n"
        printf "  2) Display Active Listening Ports & Sockets (ss -tuln)\n"
        printf "  3) Test Remote Host Reachability (ICMP Ping)\n"
        printf "  4) Measure Real-Time Bandwidth & Transfer Speed (KB/s)\n"
        printf "  0) Back to Main Menu\n"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-4]: "
        read -r net_choice

        case "${net_choice}" in
            1) show_ip_configurations ;;
            2) show_listening_ports ;;
            3) run_ping_diagnostic ;;
            4) show_bandwidth_speed ;;
            0) break ;;
            *)
                printf "%sInvalid choice! Choose 0-4.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}
