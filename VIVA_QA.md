# NexAdmin: 30 Operating Systems Viva Questions & Answers

This guide contains 30 high-frequency, rigorous viva questions and concise answers designed for university Operating Systems laboratory defense.

---

### 1. Process & Memory Fundamentals

#### Q1: What is the fundamental difference between a Process and a Thread?
**Ans:** A **process** is an independent executing program with its own dedicated virtual address space, file descriptor table, and security context managed by the kernel. A **thread** is a lightweight execution unit inside a process that shares the same virtual address space, global variables, and open files with sibling threads, having only its own thread ID, registers, and execution stack.

#### Q2: What are the primary process lifecycle states in Linux?
**Ans:**
- **R (Running/Runnable):** Actively running on CPU or waiting in the scheduler's runqueue.
- **S (Interruptible Sleep):** Waiting for an event or I/O; can be awakened by hardware events or signals.
- **D (Uninterruptible Sleep):** Waiting synchronously inside the kernel for hardware/disk I/O; ignores signals.
- **T (Stopped):** Suspended by a debugging tracer or job control signal (`SIGSTOP`/`SIGTSTP`).
- **Z (Zombie/Defunct):** Process execution finished, but its entry in the process table remains until the parent reaps its exit code.

#### Q3: What is the difference between Virtual Memory (VSZ) and Resident Set Size (RSS)?
**Ans:** **VSZ (Virtual Size)** is the total memory space the process has addressed (including shared libraries, mapped files, and unallocated stack/heap pages). **RSS (Resident Set Size)** is the exact portion of physical RAM currently occupied by the process.

#### Q4: How does Linux manage memory buffers and cache, and why is `MemAvailable` better than `MemFree`?
**Ans:** The Linux kernel uses unused physical RAM as disk cache and buffer space to accelerate I/O. `MemFree` only counts completely untouched RAM. `MemAvailable` calculates the realistic amount of memory immediately available for new applications without swapping by including reclaimable cache and slab pages.

---

### 2. Process Control, Signals & Hierarchies

#### Q5: What is a Zombie process, why does it exist, and how is it reaped?
**Ans:** A zombie process has completed execution via the `exit()` system call, freeing its memory and resources, but its entry (`task_struct`) remains in the kernel's process table so its parent can read its exit status code. It is reaped when the parent executes the `wait()` or `waitpid()` system call.

#### Q6: Can a Zombie process be killed with `kill -9`? Why or why not?
**Ans:** **No.** A zombie process is already dead; it has no running code, no thread, and no memory address space to receive or execute signals. It can only be eliminated by having its parent call `wait()`, or by terminating the parent process, which causes init (`PID 1`) to inherit and immediately reap the zombie.

#### Q7: What is an Orphan process, and what happens to it in Linux?
**Ans:** An orphan process is a living child process whose parent process terminates before the child. The Linux kernel automatically re-parents the orphan process to `PID 1` (`systemd` or `init`), which periodically invokes `wait()` to prevent long-lived zombies when orphans eventually exit.

#### Q8: Why can't `SIGKILL` (Signal 9) and `SIGSTOP` (Signal 19) be caught, blocked, or ignored?
**Ans:** POSIX and Linux design guarantees that the operating system kernel retains absolute authority over runaway or misbehaving processes. `SIGKILL` and `SIGSTOP` are intercepted and handled directly by the kernel's process scheduler; they are never delivered to user-space signal handlers.

#### Q9: What is the difference between `SIGTERM` (15) and `SIGKILL` (9)?
**Ans:** **SIGTERM (15)** is a polite termination request delivered to user space. The process can catch it, flush file buffers, close database connections, remove temporary lock files, and terminate cleanly. **SIGKILL (9)** is processed directly by the kernel, immediately deleting the task without giving the application any opportunity to perform cleanup.

#### Q10: What does State 'D' (Uninterruptible Sleep) mean, and why can't `kill -9` terminate it?
**Ans:** A process in state `D` is blocked inside kernel space waiting for a critical hardware driver or filesystem I/O transaction (such as waiting for an NFS timeout or bad disk sector). To maintain kernel data structure consistency and prevent filesystem corruption, the kernel refuses to process any asynchronous signals until the underlying device driver returns control.

#### Q11: What is the role of `PID 1` in Linux?
**Ans:** `PID 1` (traditionally `init`, modernly `systemd`) is the very first user-space process spawned directly by the Linux kernel during boot. It serves as the ancestor of all other user processes, brings up system daemons, adopts orphan processes, and continuously reaps zombie processes.

#### Q12: How does `renice` influence CPU scheduling, and what does the -20 to 19 range mean?
**Ans:** The `nice` value determines process priority in the Completely Fair Scheduler (CFS). Lower numerical values represent "less nice" (higher CPU scheduling priority), whereas higher numerical values represent "more nice" (lower CPU priority). A range of `-20` (highest priority) to `19` (lowest priority) is enforced. Only `root` can assign negative nice values.

---

### 3. Virtual Filesystems (`/proc` and `/sys`)

#### Q13: How does the `/proc` virtual filesystem work?
**Ans:** `/proc` is an in-memory Virtual Filesystem (VFS) dynamically maintained by the Linux kernel. It occupies zero physical disk space. When a user or script reads a file in `/proc` (such as `/proc/meminfo` or `/proc/stat`), the kernel executes internal diagnostic query routines and formats live kernel data structures as text streams on the fly.

#### Q14: How does NexAdmin calculate CPU utilization from `/proc/stat`?
**Ans:** NexAdmin takes two readings of `/proc/stat` separated by a 1-second interval. It sums all CPU jiffy ticks to determine $\Delta \text{total}$, and sums idle and iowait jiffies to determine $\Delta \text{idle}$. The true CPU utilization is calculated as:
$$\text{CPU \%} = \left(1 - \frac{\Delta \text{idle}}{\Delta \text{total}}\right) \times 100$$

#### Q15: What is `iowait` in `/proc/stat`?
**Ans:** `iowait` measures the percentage of time that a CPU core was completely idle while there were active disk or network I/O operations pending. High `iowait` indicates that storage hardware is a performance bottleneck.

#### Q16: How does `/sys` (sysfs) differ from `/proc`?
**Ans:** While `/proc` historically contains process state and general kernel diagnostic telemetry, `/sys` (`sysfs`) is a structured, unified device model tree introduced in Linux 2.6. It provides strict hierarchical representations of physical hardware buses, power supplies (`/sys/class/power_supply`), thermal sensors (`/sys/class/thermal`), and block storage devices.

#### Q17: What does the System Load Average (1m, 5m, 15m) represent?
**Ans:** In Linux, load average is the average number of processes that are either actively executing on a CPU core, waiting in the runqueue, or blocked in uninterruptible sleep (state D). A load average equal to the number of logical CPU cores indicates 100% capacity; anything higher indicates queuing and resource starvation.

---

### 4. Storage, Backup & Integrity Verification

#### Q18: How does an Incremental Backup work using inode modification timestamps (`mtime`)?
**Ans:** When a full backup is completed, a marker file is touched on disk to record a baseline timestamp. During an incremental backup, the system uses `find -newer <marker_file>` or `tar --newer-mtime=<marker_file>` to scan filesystem inodes and identify only those files whose `mtime` is strictly newer than the marker. Upon success, the marker's timestamp is updated to the current time.

#### Q19: Why must cryptographic checksums (MD5 or SHA-256) accompany backup archives?
**Ans:** Backup archives can suffer bit rot, storage media degradation, network packet loss, or intentional unauthorized tampering. Generating an MD5 checksum at archive creation and verifying it prior to extraction ensures mathematical data integrity and prevents corrupting live filesystems with damaged archives.

#### Q20: What is the purpose of the `-C` flag and relative paths in `tar` during backup and restore?
**Ans:** Using `-C <directory>` forces `tar` to change into that directory before archiving or extracting, stripping leading slashes (`/`). This prevents archiving absolute paths, ensuring that when an administrator restores the archive, files are safely confined to the target directory and cannot overwrite critical system root directories (`/bin`, `/etc`).

#### Q21: How does the `cron` daemon operate in Linux?
**Ans:** `crond` is a background system daemon that awakens every 60 seconds, inspects user crontab files (`/var/spool/cron/crontabs`) and system cron directories (`/etc/cron.*`), checks if the current minute, hour, day, and month match any crontab expressions, and spawns matched commands as child processes.

---

### 5. Security, Permissions & User Management

#### Q22: How does Linux enforce Discretionary Access Control (DAC)?
**Ans:** Linux binds every process to an Effective User ID (EUID) and Effective Group ID (EGID). Every filesystem inode stores an owner UID, an owning GID, and 9 permission bits (`rwxrwxrwx` for User, Group, and Others). When a process attempts an `open()` or `exec()` syscall, the kernel compares the process's EUID/EGID against the file's permission bits to permit or reject the operation (`EACCES`).

#### Q23: What is `/etc/shadow` and why is it restricted to root (`chmod 640/000`)?
**Ans:** Historically, password hashes were stored in `/etc/passwd`, which must be world-readable so commands like `ls` can map UIDs to usernames. Because world-readable hashes allowed offline dictionary and rainbow-table attacks, modern Linux systems store salted password hashes in `/etc/shadow`, which is readable strictly by root and security utilities.

#### Q24: What is password aging and how does `chage` inspect it?
**Ans:** Password aging enforces security compliance policies regarding minimum password duration, maximum lifespan before expiration, advance warning days, and account inactivity lockouts. `chage -l <user>` reads these fields from the 9 colon-separated values stored in `/etc/shadow`.

#### Q25: Why does NexAdmin store SHA-256 hashes instead of plaintext passwords?
**Ans:** Storing plaintext credentials creates a single point of catastrophic security failure. By storing only the one-way cryptographic SHA-256 hash (`printf '%s' "$password" | sha256sum`), the original password cannot be reversed even if the storage file is compromised. During login, the user's input is hashed and compared against the stored hash.

---

### 6. Networking, Shell Scripting & Best Practices

#### Q26: How does `ss` differ from legacy `netstat` when querying listening ports?
**Ans:** Legacy `netstat` reads and parses textual tables from `/proc/net/tcp` and `/proc/net/udp`, which causes performance bottlenecks on busy servers. Modern `ss` (Socket Statistics) communicates directly with the kernel using Netlink sockets, delivering much faster performance and richer TCP diagnostic data.

#### Q27: What network protocol does `ping` use, and on which OSI layer does it operate?
**Ans:** `ping` uses the **Internet Control Message Protocol (ICMP)** (specifically ICMP Echo Request, Type 8, and Echo Reply, Type 0). ICMP operates at the **Network Layer (Layer 3)** of the OSI model alongside IP, without utilizing TCP or UDP transport ports.

#### Q28: Why must variables always be double-quoted in Bash (`"$var"`)?
**Ans:** Unquoted variables undergo Word Splitting and Pathname Expansion (Globbing) by the shell parser. If a variable contains spaces, tabs, newlines, or wildcards (`*`, `?`), an unquoted variable expands into multiple distinct arguments, causing critical script syntax errors or unexpected behavior.

#### Q29: What does `set -o pipefail` do, and why is it essential for robust scripts?
**Ans:** By default in Bash, the exit status of a pipeline (`cmd1 | cmd2 | cmd3`) is determined solely by the exit status of the *last* command (`cmd3`). Enabling `set -o pipefail` ensures that if any command in the pipeline fails, the entire pipeline returns that failing exit code, preventing silent failures.

#### Q30: How does the Bash `trap` command handle operating system signals?
**Ans:** `trap '<handler_function>' INT TERM EXIT` registers an asynchronous callback with the shell. When the script receives an interrupt signal (such as `Ctrl+C` / `SIGINT` or `SIGTERM`) or reaches natural exit, the shell intercepts the signal and executes the handler function, enabling the script to restore terminal echo (`stty echo`), terminate child daemons, and write audit log entries before exiting.
