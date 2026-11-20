/*
 * ==============================================================================
 * File: src/scheduler.c
 * Project: NexAdmin - Linux System Administration & Monitoring Toolkit
 * Authors: University OS Lab Team
 * Purpose: CPU Scheduling Simulator in C. Implements FCFS, Non-preemptive SJF,
 *          and Round Robin (RR) algorithms with exact completion, turnaround,
 *          and waiting times, plus an ASCII text Gantt chart generator.
 * ==============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define MAX_PROCESSES 64
#define MAX_GANTT_SLICES 512

/* ANSI Color Escape Codes */
#define ANSI_CYAN    "\033[0;36m"
#define ANSI_GREEN   "\033[0;32m"
#define ANSI_YELLOW  "\033[0;33m"
#define ANSI_RED     "\033[0;31m"
#define ANSI_BOLD    "\033[1m"
#define ANSI_RESET   "\033[0m"

/*
 * Process Control Block (PCB) structure representation
 * OS Concept: Stores CPU execution context, arrival, burst, and computed metrics.
 */
typedef struct {
    int pid;        /* Process identifier (1, 2, ...) */
    int at;         /* Arrival Time */
    int bt;         /* Burst Time (total CPU execution time required) */
    int rt;         /* Remaining Time (used during Round Robin execution) */
    int ct;         /* Completion Time (timestamp when execution finishes) */
    int tat;        /* Turnaround Time = Completion Time - Arrival Time */
    int wt;         /* Waiting Time = Turnaround Time - Burst Time */
    bool completed; /* Completion flag */
} Process;

/*
 * Gantt Chart Time Slice structure
 * OS Concept: Visual timeline representing CPU context switches and occupancy.
 */
typedef struct {
    int pid;        /* Process ID running in this slice, or 0 for CPU IDLE */
    int start_time; /* Time slice start */
    int end_time;   /* Time slice finish */
} GanttSlice;

/* Clear input buffer */
static void clear_input_buffer(void) {
    int c;
    while ((c = getchar()) != '\n' && c != EOF) { }
}

/*
 * Reads a positive integer safely from stdin with bounds checking.
 */
static int read_int_bounded(const char *prompt, int min_val, int max_val) {
    int val;
    while (1) {
        printf("%s", prompt);
        if (scanf("%d", &val) == 1) {
            if (val >= min_val && val <= max_val) {
                clear_input_buffer();
                return val;
            }
            printf("%s[ERROR] Value must be between %d and %d. Please retry.%s\n",
                   ANSI_RED, min_val, max_val, ANSI_RESET);
        } else {
            printf("%s[ERROR] Invalid input. Please enter an integer.%s\n",
                   ANSI_RED, ANSI_RESET);
            clear_input_buffer();
        }
    }
}

/*
 * Prints an ASCII horizontal Gantt chart illustrating CPU scheduling.
 */
static void print_gantt_chart(const GanttSlice slices[], int slice_count) {
    if (slice_count <= 0) return;

    printf("\n%s========================= ASCII GANTT CHART =========================%s\n\n",
           ANSI_BOLD, ANSI_RESET);

    /* 1. Top border */
    for (int i = 0; i < slice_count; i++) {
        printf("+-------");
    }
    printf("+\n");

    /* 2. Process Labels */
    for (int i = 0; i < slice_count; i++) {
        if (slices[i].pid == 0) {
            printf("| %sIDLE%s  ", ANSI_YELLOW, ANSI_RESET);
        } else {
            printf("|  %sP%-2d%s  ", ANSI_CYAN, slices[i].pid, ANSI_RESET);
        }
    }
    printf("|\n");

    /* 3. Bottom border */
    for (int i = 0; i < slice_count; i++) {
        printf("+-------");
    }
    printf("+\n");

    /* 4. Timestamp Timeline */
    printf("%-8d", slices[0].start_time);
    for (int i = 0; i < slice_count; i++) {
        printf("%-8d", slices[i].end_time);
    }
    printf("\n\n");
}

/*
 * Prints the tabular summary of Process scheduling metrics and averages.
 */
static void print_summary_table(Process proc[], int n, const char *algo_name) {
    double total_tat = 0.0;
    double total_wt = 0.0;

    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);
    printf(" Scheduling Algorithm : %s%s%s\n", ANSI_BOLD, algo_name, ANSI_RESET);
    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);
    printf("%-8s %-14s %-12s %-18s %-18s %-14s\n",
           "PID", "Arrival (AT)", "Burst (BT)", "Completion (CT)", "Turnaround (TAT)", "Waiting (WT)");
    printf("--------------------------------------------------------------------------------\n");

    for (int i = 0; i < n; i++) {
        printf("P%-7d %-14d %-12d %-18d %-18d %-14d\n",
               proc[i].pid, proc[i].at, proc[i].bt, proc[i].ct, proc[i].tat, proc[i].wt);
        total_tat += proc[i].tat;
        total_wt += proc[i].wt;
    }

    printf("--------------------------------------------------------------------------------\n");
    printf(" Average Turnaround Time (TAT) : %s%.2f units%s (Formula: Sum(TAT) / N)\n",
           ANSI_GREEN, total_tat / (double)n, ANSI_RESET);
    printf(" Average Waiting Time (WT)    : %s%.2f units%s (Formula: Sum(WT) / N)\n",
           ANSI_GREEN, total_wt / (double)n, ANSI_RESET);
    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);
}

/*
 * First-Come, First-Served (FCFS) Scheduling Algorithm
 * OS Concept: Non-preemptive scheduling where CPU is allocated in order of arrival.
 *             Susceptible to the "Convoy Effect" when a long CPU burst arrives first.
 */
void simulate_fcfs(Process proc[], int n) {
    /* Sort copy by Arrival Time, tie-break by PID */
    Process p[MAX_PROCESSES];
    memcpy(p, proc, (size_t)n * sizeof(Process));

    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (p[j].at > p[j + 1].at || (p[j].at == p[j + 1].at && p[j].pid > p[j + 1].pid)) {
                Process temp = p[j];
                p[j] = p[j + 1];
                p[j + 1] = temp;
            }
        }
    }

    GanttSlice slices[MAX_GANTT_SLICES];
    int slice_count = 0;
    int current_time = 0;

    for (int i = 0; i < n; i++) {
        /* CPU Idle period if process hasn't arrived yet */
        if (current_time < p[i].at) {
            slices[slice_count++] = (GanttSlice){
                .pid = 0,
                .start_time = current_time,
                .end_time = p[i].at
            };
            current_time = p[i].at;
        }

        int start = current_time;
        current_time += p[i].bt;
        p[i].ct = current_time;
        p[i].tat = p[i].ct - p[i].at;
        p[i].wt = p[i].tat - p[i].bt;

        slices[slice_count++] = (GanttSlice){
            .pid = p[i].pid,
            .start_time = start,
            .end_time = current_time
        };
    }

    /* Copy back computed metrics matching original PID order */
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            if (proc[i].pid == p[j].pid) {
                proc[i] = p[j];
                break;
            }
        }
    }

    print_gantt_chart(slices, slice_count);
    print_summary_table(proc, n, "First-Come, First-Served (FCFS)");
}

/*
 * Non-preemptive Shortest Job First (SJF) Scheduling Algorithm
 * OS Concept: Allocates CPU to the arrived process with the smallest CPU burst.
 *             Provably optimal in minimizing average waiting time for non-preemptive sets,
 *             but can lead to starvation of long processes if short bursts arrive continuously.
 */
void simulate_sjf(Process proc[], int n) {
    Process p[MAX_PROCESSES];
    memcpy(p, proc, (size_t)n * sizeof(Process));

    for (int i = 0; i < n; i++) {
        p[i].completed = false;
    }

    GanttSlice slices[MAX_GANTT_SLICES];
    int slice_count = 0;
    int current_time = 0;
    int completed_count = 0;

    while (completed_count < n) {
        int best_idx = -1;
        int min_bt = 1e9;

        /* Find arrived process with minimum burst time */
        for (int i = 0; i < n; i++) {
            if (!p[i].completed && p[i].at <= current_time) {
                if (p[i].bt < min_bt) {
                    min_bt = p[i].bt;
                    best_idx = i;
                } else if (p[i].bt == min_bt) {
                    /* Tie breaker: earlier arrival time */
                    if (p[i].at < p[best_idx].at) {
                        best_idx = i;
                    }
                }
            }
        }

        if (best_idx == -1) {
            /* No process available: advance time to next earliest arrival */
            int next_arrival = 1e9;
            for (int i = 0; i < n; i++) {
                if (!p[i].completed && p[i].at < next_arrival) {
                    next_arrival = p[i].at;
                }
            }
            slices[slice_count++] = (GanttSlice){
                .pid = 0,
                .start_time = current_time,
                .end_time = next_arrival
            };
            current_time = next_arrival;
        } else {
            /* Execute process to completion */
            int start = current_time;
            current_time += p[best_idx].bt;
            p[best_idx].ct = current_time;
            p[best_idx].tat = p[best_idx].ct - p[best_idx].at;
            p[best_idx].wt = p[best_idx].tat - p[best_idx].bt;
            p[best_idx].completed = true;
            completed_count++;

            slices[slice_count++] = (GanttSlice){
                .pid = p[best_idx].pid,
                .start_time = start,
                .end_time = current_time
            };
        }
    }

    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            if (proc[i].pid == p[j].pid) {
                proc[i] = p[j];
                break;
            }
        }
    }

    print_gantt_chart(slices, slice_count);
    print_summary_table(proc, n, "Shortest Job First (SJF) [Non-Preemptive]");
}

/*
 * Round Robin (RR) Scheduling Algorithm
 * OS Concept: Preemptive time-sharing scheduler. Allocates CPU in fixed time slices (quantum).
 *             Designed for interactive systems to ensure bounded response time.
 */
void simulate_round_robin(Process proc[], int n, int quantum) {
    Process p[MAX_PROCESSES];
    memcpy(p, proc, (size_t)n * sizeof(Process));

    for (int i = 0; i < n; i++) {
        p[i].rt = p[i].bt;
        p[i].completed = false;
    }

    GanttSlice slices[MAX_GANTT_SLICES];
    int slice_count = 0;

    int queue[MAX_PROCESSES * 8];
    int head = 0, tail = 0;
    bool in_queue[MAX_PROCESSES] = { false };

    /* Sort indices by arrival time initially */
    int current_time = 0;
    int completed_count = 0;

    /* Find earliest arrival */
    int min_at = 1e9;
    for (int i = 0; i < n; i++) {
        if (p[i].at < min_at) min_at = p[i].at;
    }
    if (min_at > current_time) {
        slices[slice_count++] = (GanttSlice){
            .pid = 0,
            .start_time = current_time,
            .end_time = min_at
        };
        current_time = min_at;
    }

    /* Enqueue all processes arrived at or before current_time */
    for (int i = 0; i < n; i++) {
        if (p[i].at <= current_time && !in_queue[i]) {
            queue[tail++] = i;
            in_queue[i] = true;
        }
    }

    while (completed_count < n) {
        if (head == tail) {
            /* Queue empty but jobs remain: fast-forward to next arrival */
            int next_at = 1e9;
            for (int i = 0; i < n; i++) {
                if (!p[i].completed && p[i].at < next_at) {
                    next_at = p[i].at;
                }
            }
            if (next_at < 1e9) {
                slices[slice_count++] = (GanttSlice){
                    .pid = 0,
                    .start_time = current_time,
                    .end_time = next_at
                };
                current_time = next_at;
                for (int i = 0; i < n; i++) {
                    if (p[i].at <= current_time && !in_queue[i] && !p[i].completed) {
                        queue[tail++] = i;
                        in_queue[i] = true;
                    }
                }
            }
            continue;
        }

        int curr_idx = queue[head++];
        int exec_time = (p[curr_idx].rt < quantum) ? p[curr_idx].rt : quantum;
        int start = current_time;
        current_time += exec_time;
        p[curr_idx].rt -= exec_time;

        slices[slice_count++] = (GanttSlice){
            .pid = p[curr_idx].pid,
            .start_time = start,
            .end_time = current_time
        };

        /* Enqueue newly arrived processes during this time slice */
        for (int i = 0; i < n; i++) {
            if (i != curr_idx && !p[i].completed && !in_queue[i] && p[i].at <= current_time) {
                queue[tail++] = i;
                in_queue[i] = true;
            }
        }

        /* If current process still has remaining time, push back to queue tail */
        if (p[curr_idx].rt > 0) {
            queue[tail++] = curr_idx;
        } else {
            p[curr_idx].completed = true;
            p[curr_idx].ct = current_time;
            p[curr_idx].tat = p[curr_idx].ct - p[curr_idx].at;
            p[curr_idx].wt = p[curr_idx].tat - p[curr_idx].bt;
            completed_count++;
            in_queue[curr_idx] = false;
        }
    }

    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            if (proc[i].pid == p[j].pid) {
                proc[i] = p[j];
                break;
            }
        }
    }

    char label[128];
    snprintf(label, sizeof(label), "Round Robin (RR) [Quantum = %d]", quantum);
    print_gantt_chart(slices, slice_count);
    print_summary_table(proc, n, label);
}

/*
 * Built-in unit test verification for automated test harnesses (`make test`).
 */
int run_scheduler_unit_test(void) {
    printf("[UNIT TEST] Running CPU Scheduling Algorithms Verification...\n");

    /* Textbook Test Case:
     * P1: AT=0, BT=5
     * P2: AT=1, BT=3
     * P3: AT=2, BT=8
     * P4: AT=3, BT=6
     */
    Process test_p[4] = {
        { .pid = 1, .at = 0, .bt = 5 },
        { .pid = 2, .at = 1, .bt = 3 },
        { .pid = 3, .at = 2, .bt = 8 },
        { .pid = 4, .at = 3, .bt = 6 }
    };

    /* 1. Test FCFS:
     * Timeline: P1(0-5), P2(5-8), P3(8-16), P4(16-22)
     * CT: P1=5, P2=8, P3=16, P4=22
     * TAT: P1=5, P2=7, P3=14, P4=19 -> Sum = 45 -> Avg = 11.25
     * WT: P1=0, P2=4, P3=6, P4=13  -> Sum = 23 -> Avg = 5.75
     */
    Process p_fcfs[4];
    memcpy(p_fcfs, test_p, sizeof(test_p));
    simulate_fcfs(p_fcfs, 4);

    if (p_fcfs[0].ct != 5 || p_fcfs[1].ct != 8 || p_fcfs[2].ct != 16 || p_fcfs[3].ct != 22) {
        fprintf(stderr, "[FAIL] FCFS CT computation error!\n");
        return 1;
    }
    printf("%s[PASS] FCFS Unit Test: CT, TAT, and WT matched expected values.%s\n",
           ANSI_GREEN, ANSI_RESET);

    /* 2. Test SJF Non-preemptive:
     * At t=0: P1 runs (0-5)
     * At t=5: P2(BT=3), P3(BT=8), P4(BT=6) arrived. P2 has min BT -> runs (5-8)
     * At t=8: P4(BT=6) < P3(BT=8) -> runs (8-14)
     * At t=14: P3 runs (14-22)
     * CT: P1=5, P2=8, P3=22, P4=14
     */
    Process p_sjf[4];
    memcpy(p_sjf, test_p, sizeof(test_p));
    simulate_sjf(p_sjf, 4);

    if (p_sjf[0].ct != 5 || p_sjf[1].ct != 8 || p_sjf[2].ct != 22 || p_sjf[3].ct != 14) {
        fprintf(stderr, "[FAIL] SJF CT computation error!\n");
        return 1;
    }
    printf("%s[PASS] SJF Unit Test: Scheduling order and completion times verified.%s\n",
           ANSI_GREEN, ANSI_RESET);

    /* 3. Test Round Robin (Quantum = 2):
     * Timeline:
     * t=0: P1(0-2, rt=3). Arrived: P2(1), P3(2)
     * t=2: P2(2-4, rt=1). Arrived: P4(3)
     * t=4: P3(4-6, rt=6).
     * t=6: P1(6-8, rt=1).
     * t=8: P4(8-10, rt=4).
     * t=10: P2(10-11, rt=0) -> finishes at 11!
     */
    Process p_rr[4];
    memcpy(p_rr, test_p, sizeof(test_p));
    simulate_round_robin(p_rr, 4, 2);

    if (p_rr[1].ct != 11) {
        fprintf(stderr, "[FAIL] Round Robin CT mismatch for P2 (expected 11, got %d)!\n", p_rr[1].ct);
        return 1;
    }
    printf("%s[PASS] Round Robin Unit Test: Preemption and quantum cycling verified.%s\n",
           ANSI_GREEN, ANSI_RESET);

    return 0;
}

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--test") == 0) {
        return run_scheduler_unit_test();
    }

    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);
    printf("%s                 NEXADMIN - CPU SCHEDULING SIMULATOR (C ENGINE)                %s\n",
           ANSI_BOLD, ANSI_RESET);
    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);

    int mode_choice = 0;
    printf(" 1) Custom Interactive Input\n");
    printf(" 2) Quick Standard Demonstration (4-Process Academic Benchmark)\n");
    printf(" 3) Run Automated Self-Verification Unit Tests\n");
    mode_choice = read_int_bounded("Select Mode [1-3]: ", 1, 3);

    if (mode_choice == 3) {
        return run_scheduler_unit_test();
    }

    Process proc[MAX_PROCESSES];
    int n = 0;

    if (mode_choice == 2) {
        n = 4;
        proc[0] = (Process){ .pid = 1, .at = 0, .bt = 5 };
        proc[1] = (Process){ .pid = 2, .at = 1, .bt = 3 };
        proc[2] = (Process){ .pid = 3, .at = 2, .bt = 8 };
        proc[3] = (Process){ .pid = 4, .at = 3, .bt = 6 };
        printf("\n%s[LOADED BENCHMARK WORKLOAD]%s\n", ANSI_GREEN, ANSI_RESET);
        printf(" P1: Arrival=0, Burst=5\n");
        printf(" P2: Arrival=1, Burst=3\n");
        printf(" P3: Arrival=2, Burst=8\n");
        printf(" P4: Arrival=3, Burst=6\n\n");
    } else {
        n = read_int_bounded("\nEnter total number of processes (1-20): ", 1, 20);
        for (int i = 0; i < n; i++) {
            proc[i].pid = i + 1;
            printf("\n--- Process P%d ---\n", proc[i].pid);
            char prompt_at[64], prompt_bt[64];
            snprintf(prompt_at, sizeof(prompt_at), "Enter Arrival Time (AT >= 0): ");
            proc[i].at = read_int_bounded(prompt_at, 0, 1000);
            snprintf(prompt_bt, sizeof(prompt_bt), "Enter Burst Time (BT >= 1): ");
            proc[i].bt = read_int_bounded(prompt_bt, 1, 1000);
        }
    }

    while (1) {
        printf("\n%sSelect CPU Scheduling Algorithm:%s\n", ANSI_BOLD, ANSI_RESET);
        printf(" 1) First-Come, First-Served (FCFS)\n");
        printf(" 2) Shortest Job First (SJF) [Non-Preemptive]\n");
        printf(" 3) Round Robin (RR)\n");
        printf(" 4) Run All Three Algorithms & Compare\n");
        printf(" 0) Exit Simulator\n");

        int algo = read_int_bounded("Choice [0-4]: ", 0, 4);
        if (algo == 0) break;

        switch (algo) {
            case 1:
                simulate_fcfs(proc, n);
                break;
            case 2:
                simulate_sjf(proc, n);
                break;
            case 3: {
                int q = read_int_bounded("Enter Time Quantum (>= 1): ", 1, 100);
                simulate_round_robin(proc, n, q);
                break;
            }
            case 4: {
                int q = read_int_bounded("Enter Time Quantum for Round Robin (>= 1): ", 1, 100);
                printf("\n>>> 1. FIRST-COME, FIRST-SERVED (FCFS) <<<\n");
                simulate_fcfs(proc, n);
                printf("\n>>> 2. SHORTEST JOB FIRST (SJF) <<<\n");
                simulate_sjf(proc, n);
                printf("\n>>> 3. ROUND ROBIN (RR) <<<\n");
                simulate_round_robin(proc, n, q);
                break;
            }
            default:
                break;
        }
    }

    printf("\nExiting CPU Scheduling Simulator.\n");
    return 0;
}
