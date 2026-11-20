# NexAdmin: Linux System Administration & Monitoring Toolkit

NexAdmin is a production-grade, terminal-based Linux system administration, real-time telemetry monitoring, and disaster recovery toolkit engineered purely in POSIX-compliant Bash. Designed for university Operating Systems laboratory defense and enterprise server auditing, NexAdmin provides deep observability into Linux kernel internals (`/proc` and `/sys`) without requiring external dependencies, Python runtimes, or network connectivity.

---

## 🏛️ System Architecture

```
nexadmin/
├── nexadmin.sh        # Primary entry point: CLI flags, SHA-256 login, dashboard summary, main loop
├── config.conf        # User-configurable alert thresholds and operational timers
├── lib/
│   └── common.sh      # Shared library: ANSI colors, audit logger, validators, progress bars, root checks
├── modules/
│   ├── monitor.sh     # System telemetry: CPU (jiffies delta), RAM (MemAvailable), Disks, Battery, Temp
│   ├── process.sh     # Process inspection: State breakdown, Top 10 CPU/RAM, search, PID hierarchy
│   ├── procmgr.sh     # Process control: SIGTERM, SIGKILL, SIGSTOP, SIGCONT, renice, zombie/D-state audits
│   ├── alert.sh       # Health engine: Threshold evaluation, alert logs, background daemon
│   ├── backup.sh      # Disaster recovery: Full/Incr tar.gz, MD5 verification, pruning, crontab automation
│   ├── users.sh       # Identity & access: Accounts, groups, who, last, chage password aging, useradd/userdel
│   ├── logs.sh        # Forensics & diagnostics: Failed login attacks, top source IPs, syslog/journald
│   ├── network.sh     # Network diagnostics: IP routes, DNS, ss listening sockets, ping, /proc/net/dev I/O
│   └── report.sh      # Historical telemetry: CSV time-series, ASCII charts, System Health Reports
├── data/              # Runtime state: history.csv, alerts.log, password hash, PID files
├── backups/           # Compressed archives (.tar.gz) and cryptographic checksums (.md5)
├── reports/           # Timestamped System Health Audit reports (.txt) and CSV exports
├── nexadmin.log       # Centralized audit log tracking all user and daemon activities
├── README.md          # Technical documentation and architecture specification
├── TESTING.md         # Comprehensive test protocols, test cases, and verification results
├── EXPLAIN_BN.md      # Full Bengali explanation of all modules and functions for Viva defense
└── VIVA_QA.md         # 30 high-yield Operating Systems viva defense questions and answers
```

---

## 🚀 Key Features

### 1. Live Telemetry & Hardware Observability (`monitor.sh`)
- **Kernel Jiffies CPU Calculation**: Derives true CPU utilization by computing the differential of non-idle vs total CPU time over a sampling window directly from `/proc/stat`.
- **Accurate Memory Accounting**: Computes active RAM usage using `MemAvailable` from `/proc/meminfo` (accounting for reclaimable kernel buffers and cached pages).
- **Filesystem & Hardware Sensors**: Inspects physical disk volume usage (`df`), ACPI battery state (`/sys/class/power_supply/BAT*`), and thermal zones (`/sys/class/thermal/thermal_zone*`).
- **Interactive Live Monitor**: Auto-refreshing terminal dashboard with dynamic ANSI-colored text progress bars (`[#####-----] 50%`) and clean 'q' quit binding.

### 2. Process Telemetry & Inspection (`process.sh`)
- **Process State Mapping**: Maps Linux task states (`R`, `S`, `D`, `T`, `Z`, `I`) to human-readable explanations.
- **Top Resource Consumers**: Instantaneous sorting of top 10 CPU and Memory consumers.
- **Process Hierarchy Inspector**: Given any PID, extracts owner, resident RAM (`VmRSS`), virtual size (`VmSize`), start time, active thread count, executable command line, parent process name, and child process tree.

### 3. Process Control & Lifecycle Management (`procmgr.sh`)
- **Signal Dispatching**: Supports graceful termination (`SIGTERM` 15), uncatchable force kill (`SIGKILL` 9), execution suspension (`SIGSTOP` 19), and execution resumption (`SIGCONT` 18).
- **Dynamic Priority Scheduling**: Adjusts process CPU niceness (`renice` from -20 to 19).
- **Kernel Safety Protections**: Strictly blocks attempts to terminate `PID 1` (init/systemd), the running NexAdmin process (`$$`), or its parent shell (`$PPID`).
- **Zombie & Uninterruptible Sleep Diagnostics**: Identifies defunct zombie processes with their parent PIDs, explaining wait/reaping mechanics; identifies D-state processes blocked on kernel I/O.

### 4. Autonomous Threshold Alerting (`alert.sh`)
- Real-time comparison of CPU, RAM, Disk, Load Average, and Battery against `config.conf` thresholds.
- Appends structured warning entries to `data/alerts.log`.
- Autonomous background monitoring daemon with PID lifecycle management (`start_alert_daemon` / `stop_alert_daemon`).

### 5. Enterprise Backup & Disaster Recovery (`backup.sh`)
- **Full Backups**: Compressed `.tar.gz` archives with relative target isolation (preventing path traversal).
- **Incremental Backups**: Tracks file changes via modification timestamps (`mtime`) against baseline marker files (`find -newer`).
- **Cryptographic Verification**: Computes and audits MD5 checksums; rejects corrupted or tampered archives before restoration.
- **Lifecycle Retention**: Prunes archives older than $N$ days (`BACKUP_RETENTION_DAYS`).
- **Crontab Scheduling**: Generates and installs automated daily cron jobs.

### 6. Identity & User Administration (`users.sh`)
- Audits `/etc/passwd` (UID >= 1000) and `/etc/group`.
- Shows active sessions (`who`), historical logins (`last`), and password aging policies (`chage -l`).
- Safe user provisioning (`useradd`, `userdel -r`, `usermod -L/-U/-aG`) with regex username validation and root protections.
- Graceful privilege degradation: non-root users can access all read-only inspection menus while administrative mutations display informative permission notices.

### 7. Security Forensics & System Logs (`logs.sh`)
- Parses `/var/log/auth.log` or `/var/log/secure` for brute force authentication failures.
- Extracts and aggregates top attacking source IP addresses (`grep`, `awk`, `sort`, `uniq -c`).
- Filters system events by priority or custom keywords via `journalctl` or `/var/log/syslog`.

### 8. Network Diagnostics & Bandwidth Meter (`network.sh`)
- Inspects network interfaces, IP addresses, default gateway routes, and `/etc/resolv.conf` DNS nameservers.
- Displays TCP/UDP listening sockets via `ss -tuln`.
- Automated ICMP ping reachability diagnostics with latency analysis.
- Live network interface transfer rates (KB/s download and upload) sampled from `/proc/net/dev`.

### 9. Historical Telemetry & Health Reporting (`report.sh`)
- Periodically records time-series metrics (`Timestamp,CPU,RAM,Disk,Processes`) to `data/history.csv`.
- Renders terminal-based ASCII bar charts representing CPU trends over the last 20 snapshots.
- Compiles timestamped comprehensive System Health Audit reports into `reports/health_<timestamp>.txt`.

---

## 🔒 Security Model

1. **SHA-256 Master Password**: On first launch, the administrator creates a master password. Only its SHA-256 hash is stored in `data/.password.hash` with `chmod 600`.
2. **Brute Force Lockout**: Maximum 3 consecutive authentication attempts before termination.
3. **Strict Policy Enforcement**: Bypassing authentication (`--no-login`) is explicitly prohibited.
4. **Input Sanitization**: All user inputs (PIDs, usernames, filenames, numbers) are strictly validated via POSIX regex. No `eval` statements are utilized.
5. **Privilege Separation**: Unprivileged execution is fully supported; read-only telemetry operates seamlessly, while administrative operations warn and instruct the operator to run with `sudo`.

---

## 🛠️ Installation & Getting Started

### Prerequisites
NexAdmin runs on standard Ubuntu, Debian, or generic Linux distributions with standard core utilities (`bash`, `awk`, `grep`, `sed`, `ps`, `tar`, `gzip`, `ip`, `ss`, `ping`). No internet access or extra package installation is required.

### Quick Start
```bash
# Navigate to the project directory
cd nexadmin

# Grant execution permission
chmod +x nexadmin.sh

# Launch the toolkit
./nexadmin.sh
```

### Command-Line Arguments
```bash
./nexadmin.sh --help       # Display usage documentation and options
./nexadmin.sh --version    # Display version and academic attribution
```

---

## ⚙️ Configuration Reference (`config.conf`)

| Parameter | Default | Description |
|---|---|---|
| `CPU_THRESHOLD` | `80` | CPU utilization percentage threshold for warning alerts |
| `RAM_THRESHOLD` | `85` | RAM utilization percentage threshold for warning alerts |
| `DISK_THRESHOLD` | `90` | Root partition disk usage percentage threshold |
| `BATTERY_THRESHOLD` | `20` | Low battery percentage threshold (when discharging) |
| `LOAD_THRESHOLD` | `2.0` | 1-minute system load average threshold |
| `REFRESH_INTERVAL` | `3` | Live System Monitor refresh interval in seconds |
| `ALERT_CHECK_INTERVAL` | `10` | Interval between background alert daemon checks |
| `HISTORY_RECORD_INTERVAL` | `30` | Interval between background telemetry snapshots |
| `BACKUP_RETENTION_DAYS` | `7` | Number of days before backup archives are marked expired |
| `DEFAULT_BACKUP_DIR` | `/tmp/nexadmin_demo` | Default path offered for backup and crontab operations |

---

## 🎓 Academic Defense & Viva Resources
- **[TESTING.md](file:///run/media/sajjad-mahmud/Software/University Resources/NextAdmin/nexadmin/TESTING.md)**: Complete testing protocol, validation methodology, and proof of robustness.
- **[EXPLAIN_BN.md](file:///run/media/sajjad-mahmud/Software/University Resources/NextAdmin/nexadmin/EXPLAIN_BN.md)**: Line-by-line Bengali explanation of every module, function, and OS algorithm.
- **[VIVA_QA.md](file:///run/media/sajjad-mahmud/Software/University Resources/NextAdmin/nexadmin/VIVA_QA.md)**: 30 likely Operating Systems viva defense questions with clear answers.
# NexAdmin
