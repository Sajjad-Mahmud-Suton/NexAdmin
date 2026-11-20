# NexAdmin: Linux System Administration & Academic OS Simulation Toolkit

NexAdmin is a production-grade, dual-engine Linux system administration, real-time telemetry monitoring, disaster recovery, and academic OS simulation toolkit. Engineered using **Bash** for native Linux system administration and **C (C11)** for high-performance academic operating system algorithm simulations, NexAdmin provides deep observability into Linux kernel internals (`/proc` and `/sys`) and theoretical OS algorithms without requiring external packages or internet connectivity.

---

## 🏛️ System Architecture

```
nexadmin/
├── nexadmin.sh        # Primary entry point: CLI flags, SHA-256 login, dashboard summary, main loop
├── Makefile           # Build system for C engines: make, make test, make clean, make run
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
├── src/               # Native C academic algorithm simulators
│   ├── scheduler.c    # CPU Scheduling: FCFS, Non-preemptive SJF, Round Robin, ASCII Gantt charts
│   ├── paging.c       # Page Replacement: FIFO, LRU, Optimal, frame-by-frame trace, hit/fault ratios
│   └── deadlock.c     # Deadlock Avoidance: Banker's Safety Algorithm, Need matrix, Resource-Request
├── bin/               # Compiled native binaries: scheduler, paging, deadlock
├── data/              # Runtime state: history.csv, alerts.log, password hash, PID files
├── backups/           # Storage repository for compressed archives (.tar.gz) and checksums (.md5)
├── reports/           # Timestamped health audit reports (.txt) and CSV exports
├── nexadmin.log       # Centralized audit log tracking all user and daemon activities
├── README.md          # Technical documentation and architecture specification
├── TESTING.md         # Comprehensive test protocols, test cases, and verification results
├── EXPLAIN_BN.md      # Full Bengali explanation of all modules and functions for Viva defense
└── VIVA_QA.md         # 40 high-yield Operating Systems viva defense questions and answers
```

---

## 🚀 Key Features

### A. Academic OS Algorithm Simulators (Native C Engine)
1. **CPU Scheduling Simulator (`src/scheduler.c` -> `bin/scheduler`)**:
   - Algorithms: First-Come, First-Served (**FCFS**), Non-preemptive Shortest Job First (**SJF**), and **Round Robin (RR)**.
   - Computes Completion Time ($CT$), Turnaround Time ($TAT = CT - AT$), and Waiting Time ($WT = TAT - BT$).
   - Calculates Average Turnaround Time and Average Waiting Time.
   - Generates horizontal text-based ASCII **Gantt Charts** illustrating timeline slices and CPU idle intervals.
2. **Virtual Memory Page Replacement Simulator (`src/paging.c` -> `bin/paging`)**:
   - Policies: **FIFO**, **LRU** (Least Recently Used), and **Optimal** (Belady's MIN).
   - Generates full frame-by-frame memory trace tables showing frame contents and `HIT` / `FAULT` indicators.
   - Tracks Page Hits, Page Faults, Hit Ratio %, and Fault Ratio %.
   - Compares all three algorithms side-by-side on custom or classic 20-page benchmark reference strings.
3. **Deadlock Avoidance & Banker's Algorithm (`src/deadlock.c` -> `bin/deadlock`)**:
   - Implements **Dijkstra's Banker's Algorithm** for deadlock avoidance.
   - Automatically derives the **Need Matrix** ($Need = Max - Allocation$) and validates system state matrices.
   - Determines **Safe vs Unsafe states** and derives safe execution sequences (e.g. `< P1 -> P3 -> P4 -> P0 -> P2 >`).
   - Simulates dynamic **Resource-Request algorithm** to safely evaluate tentative allocations.

### B. Real Linux System Administration Modules (Pure Bash Engine)
1. **Live Telemetry & Hardware Observability (`monitor.sh`)**:
   - CPU % via `/proc/stat` jiffies delta, RAM % via `/proc/meminfo` (`MemAvailable`), disk partitions (`df`), battery, and thermal sensors.
2. **Process Telemetry & Control (`process.sh` & `procmgr.sh`)**:
   - Top 10 CPU/RAM consumers, PID details inspection, parent/child trees.
   - Signal dispatching: `SIGTERM` (15), `SIGKILL` (9), `SIGSTOP` (19), `SIGCONT` (18), and `renice`.
   - Kernel safety guardrails: strictly protects `PID 1` (init/systemd), the running script (`$$`), and parent shell.
   - Zombie process auditor and uninterruptible sleep (D-state) diagnostics.
3. **Autonomous Threshold Alerting (`alert.sh`)**:
   - Evaluates thresholds from `config.conf` and manages a background alert daemon.
4. **Disaster Recovery & Backup Manager (`backup.sh`)**:
   - Full and incremental tar/gzip backups with modification time (`mtime`) markers.
   - Cryptographic MD5 checksum verification; rejects corrupted or tampered archives.
   - Lifecycle retention pruning and Crontab daily backup scheduling.
5. **Identity & User Administration (`users.sh`)**:
   - Audits `/etc/passwd`, `/etc/group`, `who`, `last`, and `chage -l` password aging.
   - Safe user provisioning with regex validation and root protection.
6. **Security Forensics & Logs (`logs.sh`)**:
   - Detects brute-force SSH/local login attacks and extracts top attacking source IPs from `/var/log/auth.log`.
7. **Network Diagnostics (`network.sh`)**:
   - Interface IPs, default routes, DNS servers, `ss -tuln` listening sockets, ping latency, and `/proc/net/dev` transfer speed.
8. **Historical Telemetry & Health Reports (`report.sh`)**:
   - Time-series CSV logging, ASCII bar charts, and compiles comprehensive system health reports.

---

## 🛠️ Build & Installation

### Prerequisites
- Standard Linux (Ubuntu / Debian / Generic).
- Standard build tools: `gcc` and `make`.
- No third-party packages or internet connection required.

### Building & Running
```bash
# 1. Build all C simulators
make

# 2. Run automated self-verification unit tests
make test

# 3. Launch NexAdmin
./nexadmin.sh
# or simply:
make run
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
