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

---

### 7. Academic OS Algorithms (C Engine Simulators)

#### Q31: What is the Convoy Effect in FCFS CPU scheduling?
**Ans:** The Convoy Effect occurs in non-preemptive First-Come, First-Served scheduling when a CPU-intensive process with a very large burst time arrives just before multiple short, I/O-bound processes. The short processes become stuck behind the long process in the ready queue, leading to low CPU and device utilization and severely inflated average waiting times.

#### Q32: Why is Shortest Job First (SJF) provably optimal for average waiting time, and what is its major drawback?
**Ans:** SJF minimizes average waiting time because moving a process with a shorter burst time ahead of a longer one reduces the waiting time of the short process by more than it increases the waiting time of the long process. Its primary drawback is **Starvation**: if short jobs arrive continuously, long processes may never receive CPU execution. Furthermore, true burst times cannot be known in advance in general-purpose operating systems.

#### Q33: How does the choice of Time Quantum impact Round Robin scheduling performance?
**Ans:** If the quantum is extremely large, Round Robin degenerates into FCFS. If the quantum is extremely small, the system suffers massive CPU overhead due to frequent context switching. As a rule of thumb, the time quantum should be slightly greater than the typical interactive CPU burst so that roughly 80% of CPU bursts finish within a single time slice.

#### Q34: What is Belady's Anomaly in Page Replacement, and why does FIFO suffer from it while LRU does not?
**Ans:** **Belady's Anomaly** is the counter-intuitive phenomenon where increasing the number of physical page frames results in an *increase* in the number of page faults for certain reference strings. FIFO suffers from Belady's Anomaly because it evicts pages strictly based on arrival order regardless of usage locality. LRU does not suffer from it because LRU is a **Stack Algorithm**, meaning the set of pages in an $N$-frame memory is always a strict subset of the pages in an $(N+1)$-frame memory.

#### Q35: What is a Stack Algorithm in virtual memory management?
**Ans:** A stack algorithm is a page replacement policy where the set of pages in memory for $n$ frames is always a subset of the pages that would be in memory with $n+1$ frames for the exact same page reference string at any point in time. Stack algorithms (such as LRU and Optimal) are mathematically proven to never exhibit Belady's Anomaly.

#### Q36: Why can't Belady's Optimal Page Replacement algorithm be implemented in real operating systems?
**Ans:** The Optimal algorithm requires clairvoyant, omniscient knowledge of future memory reference requests (replacing the page that will not be used for the longest period in the future). Because general-purpose operating systems cannot predict arbitrary future user inputs and memory branches, Optimal cannot be deployed online; it serves as a theoretical gold standard to measure the efficiency of online algorithms like LRU.

#### Q37: What are Coffman's four necessary and sufficient conditions for Deadlock?
**Ans:**
1. **Mutual Exclusion:** At least one resource is held in a non-shareable mode.
2. **Hold and Wait:** A process holds at least one resource while waiting to acquire additional resources held by others.
3. **No Preemption:** Resources cannot be forcibly confiscated; they can only be released voluntarily by the holding process.
4. **Circular Wait:** A closed circular chain of processes exists where each process waits for a resource held by the next process in the cycle.

#### Q38: What is the difference between Deadlock Prevention and Deadlock Avoidance?
**Ans:** **Deadlock Prevention** designs static constraints into system protocols to ensure that at least one of the four Coffman conditions can never hold (e.g., resource ordering to eliminate circular wait). **Deadlock Avoidance** dynamically examines every resource request at runtime (using algorithms like Dijkstra's Banker's Algorithm) and only grants a request if the resulting system state remains strictly **Safe**.

#### Q39: Is an Unsafe State in Banker's Algorithm identical to a Deadlock state?
**Ans:** **No.** An unsafe state is not necessarily a deadlocked state; rather, an unsafe state is a state from which the operating system cannot guarantee that a deadlock will not occur. All deadlocked states are unsafe, but not all unsafe states are currently deadlocked (processes might finish without claiming their maximum declared demand).

#### Q40: How does Banker's Resource-Request algorithm decide whether a request can be granted?
**Ans:**
1. If $Request_i \le Need_i$, proceed; else throw error (process exceeded maximum claim).
2. If $Request_i \le Available$, proceed; else process $P_i$ must wait (insufficient free resources).
3. Pretend to allocate by adjusting vectors:
   $$Available = Available - Request_i$$
   $$Allocation_i = Allocation_i + Request_i$$
   $$Need_i = Need_i - Request_i$$
4. Run the Safety Algorithm on this tentative state. If safe, grant the resources; if unsafe, roll back the tentative state and force $P_i$ to wait.
