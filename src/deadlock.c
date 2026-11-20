/*
 * ==============================================================================
 * File: src/deadlock.c
 * Project: NexAdmin - Linux System Administration & Monitoring Toolkit
 * Authors: University OS Lab Team
 * Purpose: Deadlock Avoidance Simulator in C. Implements Edsger Dijkstra's
 *          Banker's Safety Algorithm, Need Matrix derivation, Safe/Unsafe state
 *          auditing, and dynamic Resource-Request safety evaluation.
 * ==============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define MAX_PROC 16
#define MAX_RES  10

/* ANSI Color Escape Codes */
#define ANSI_CYAN    "\033[0;36m"
#define ANSI_GREEN   "\033[0;32m"
#define ANSI_YELLOW  "\033[0;33m"
#define ANSI_RED     "\033[0;31m"
#define ANSI_BOLD    "\033[1m"
#define ANSI_RESET   "\033[0m"

typedef struct {
    int n; /* Number of processes */
    int m; /* Number of resource types */
    int alloc[MAX_PROC][MAX_RES];
    int max[MAX_PROC][MAX_RES];
    int need[MAX_PROC][MAX_RES];
    int avail[MAX_RES];
} SystemState;

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
 * Computes Need Matrix: Need[i][j] = Max[i][j] - Allocation[i][j]
 * OS Concept: The remaining resources process i may request before releasing all resources.
 */
void compute_need_matrix(SystemState *sys) {
    for (int i = 0; i < sys->n; i++) {
        for (int j = 0; j < sys->m; j++) {
            sys->need[i][j] = sys->max[i][j] - sys->alloc[i][j];
            if (sys->need[i][j] < 0) {
                sys->need[i][j] = 0;
            }
        }
    }
}

/*
 * Displays current state matrices (Allocation, Maximum, Need, Available).
 */
void print_system_state(const SystemState *sys) {
    printf("\n%s========================= SYSTEM RESOURCE MATRICES =========================%s\n",
           ANSI_CYAN, ANSI_RESET);
    printf("%-8s | ", "PROCESS");

    /* Headers for Allocation */
    printf("ALLOCATION ");
    for (int j = 0; j < sys->m; j++) printf("%c ", 'A' + j);
    printf("| ");

    /* Headers for Maximum */
    printf("MAXIMUM ");
    for (int j = 0; j < sys->m; j++) printf("%c ", 'A' + j);
    printf("| ");

    /* Headers for Need */
    printf("NEED (Max-Alloc) ");
    for (int j = 0; j < sys->m; j++) printf("%c ", 'A' + j);
    printf("| ");

    /* Headers for Available */
    printf("AVAILABLE\n");
    printf("---------+-------------");
    for (int j = 0; j < sys->m; j++) printf("--");
    printf("+---------");
    for (int j = 0; j < sys->m; j++) printf("--");
    printf("+------------------");
    for (int j = 0; j < sys->m; j++) printf("--");
    printf("+----------\n");

    for (int i = 0; i < sys->n; i++) {
        printf("P%-7d |             ", i);
        for (int j = 0; j < sys->m; j++) {
            printf("%-2d", sys->alloc[i][j]);
        }
        printf("|         ");
        for (int j = 0; j < sys->m; j++) {
            printf("%-2d", sys->max[i][j]);
        }
        printf("|                  ");
        for (int j = 0; j < sys->m; j++) {
            printf("%-2d", sys->need[i][j]);
        }
        printf("| ");

        if (i == 0) {
            for (int j = 0; j < sys->m; j++) {
                printf("%c:%d ", 'A' + j, sys->avail[j]);
            }
        }
        printf("\n");
    }
    printf("%s============================================================================%s\n\n",
           ANSI_CYAN, ANSI_RESET);
}

/*
 * Banker's Safety Algorithm
 * OS Concept: Determines whether a state is safe or unsafe.
 *             A state is SAFE if there exists at least one sequence of process executions
 *             such that every process can satisfy its maximum demand and terminate without deadlock.
 */
bool is_system_safe(const SystemState *sys, int safe_seq[], bool verbose) {
    int work[MAX_RES];
    bool finish[MAX_PROC] = { false };
    int count = 0;

    for (int j = 0; j < sys->m; j++) {
        work[j] = sys->avail[j];
    }

    if (verbose) {
        printf("%s[EXECUTING BANKER'S SAFETY AUDIT]%s\n", ANSI_BOLD, ANSI_RESET);
        printf("Initial Work Vector: [ ");
        for (int j = 0; j < sys->m; j++) printf("%c:%d ", 'A' + j, work[j]);
        printf("]\n\n");
    }

    while (count < sys->n) {
        bool found = false;

        for (int i = 0; i < sys->n; i++) {
            if (!finish[i]) {
                /* Check if Need[i] <= Work */
                bool can_satisfy = true;
                for (int j = 0; j < sys->m; j++) {
                    if (sys->need[i][j] > work[j]) {
                        can_satisfy = false;
                        break;
                    }
                }

                if (can_satisfy) {
                    /* Process can execute to completion and release all allocated resources */
                    for (int j = 0; j < sys->m; j++) {
                        work[j] += sys->alloc[i][j];
                    }
                    safe_seq[count++] = i;
                    finish[i] = true;
                    found = true;

                    if (verbose) {
                        printf(" -> Process %sP%d%s satisfies condition (Need <= Work). Executes and releases resources.\n",
                               ANSI_GREEN, i, ANSI_RESET);
                        printf("    New Work Vector: [ ");
                        for (int j = 0; j < sys->m; j++) printf("%c:%d ", 'A' + j, work[j]);
                        printf("]\n");
                    }
                    break;
                }
            }
        }

        if (!found) {
            /* No process could satisfy its needs with available work resources */
            break;
        }
    }

    if (count == sys->n) {
        if (verbose) {
            printf("\n%s[SAFE STATE CONFIRMED]%s The system is in a verified safe state.\n",
                   ANSI_GREEN, ANSI_RESET);
            printf("%sSafe Execution Sequence:%s < ", ANSI_BOLD, ANSI_RESET);
            for (int i = 0; i < sys->n; i++) {
                printf("%sP%d%s%s", ANSI_GREEN, safe_seq[i], ANSI_RESET, (i < sys->n - 1) ? " -> " : " ");
            }
            printf(">\n\n");
        }
        return true;
    } else {
        if (verbose) {
            printf("\n%s[CRITICAL ALERT: UNSAFE STATE]%s Deadlock potential detected!\n",
                   ANSI_RED, ANSI_RESET);
            printf("No safe sequence exists. The following processes are deadlocked / starved:\n");
            for (int i = 0; i < sys->n; i++) {
                if (!finish[i]) {
                    printf(" - %sP%d%s (Needs more than available resources)\n", ANSI_RED, i, ANSI_RESET);
                }
            }
            printf("\n");
        }
        return false;
    }
}

/*
 * Banker's Resource-Request Algorithm
 * OS Concept: Decides whether an instantaneous resource request by process P_k
 *             can be safely granted immediately or if P_k must wait to prevent deadlock.
 */
void evaluate_resource_request(SystemState *sys) {
    int pid = read_int_bounded("\nEnter Process ID making request (0 to N-1): ", 0, sys->n - 1);
    int req[MAX_RES];

    printf("Enter resource request vector for P%d (%d resource types):\n", pid, sys->m);
    for (int j = 0; j < sys->m; j++) {
        char prompt[64];
        snprintf(prompt, sizeof(prompt), "Units of Resource %c: ", 'A' + j);
        req[j] = read_int_bounded(prompt, 0, 100);
    }

    /* Condition 1: Request <= Need */
    for (int j = 0; j < sys->m; j++) {
        if (req[j] > sys->need[pid][j]) {
            printf("\n%s[ERROR] Process P%d exceeded its maximum declared claim for Resource %c! Request denied.%s\n",
                   ANSI_RED, pid, 'A' + j, ANSI_RESET);
            return;
        }
    }

    /* Condition 2: Request <= Available */
    for (int j = 0; j < sys->m; j++) {
        if (req[j] > sys->avail[j]) {
            printf("\n%s[RESOURCE STARVATION] Resource %c not available in sufficient quantity. Process P%d must wait.%s\n",
                   ANSI_YELLOW, 'A' + j, pid, ANSI_RESET);
            return;
        }
    }

    /* Tentative Allocation */
    SystemState temp = *sys;
    for (int j = 0; j < sys->m; j++) {
        temp.avail[j] -= req[j];
        temp.alloc[pid][j] += req[j];
        temp.need[pid][j] -= req[j];
    }

    int safe_seq[MAX_PROC];
    printf("\nTentatively allocating resources and testing system safety...\n");

    if (is_system_safe(&temp, safe_seq, true)) {
        printf("%s[SUCCESS] Request can be safely granted immediately! Committing allocation.%s\n",
               ANSI_GREEN, ANSI_RESET);
        *sys = temp;
        print_system_state(sys);
    } else {
        printf("%s[REQUEST REJECTED] Granting this request would transition the system into an UNSAFE STATE!%s\n",
               ANSI_RED, ANSI_RESET);
        printf("Process P%d must wait until other processes release resources.\n", pid);
    }
}

/*
 * Automated unit test suite verifying textbook safe and unsafe states.
 */
int run_deadlock_unit_test(void) {
    printf("[UNIT TEST] Running Banker's Deadlock Algorithm Verification...\n");

    /* Classic Silberschatz OS Textbook Benchmark:
     * 5 Processes (P0..P4), 3 Resource Types (A, B, C)
     * Allocation:
     * P0: 0 1 0
     * P1: 2 0 0
     * P2: 3 0 2
     * P3: 2 1 1
     * P4: 0 0 2
     * Max:
     * P0: 7 5 3
     * P1: 3 2 2
     * P2: 9 0 2
     * P3: 2 2 2
     * P4: 4 3 3
     * Available: 3 3 2
     * Expected Safe Sequence: P1, P3, P4, P0, P2 (or P1, P3, P4, P2, P0)
     */
    SystemState test_sys = {
        .n = 5,
        .m = 3,
        .alloc = {
            {0, 1, 0},
            {2, 0, 0},
            {3, 0, 2},
            {2, 1, 1},
            {0, 0, 2}
        },
        .max = {
            {7, 5, 3},
            {3, 2, 2},
            {9, 0, 2},
            {2, 2, 2},
            {4, 3, 3}
        },
        .avail = {3, 3, 2}
    };
    compute_need_matrix(&test_sys);

    int safe_seq[MAX_PROC];
    bool safe = is_system_safe(&test_sys, safe_seq, false);

    if (!safe) {
        fprintf(stderr, "[FAIL] Banker's algorithm failed: Standard benchmark reported as unsafe!\n");
        return 1;
    }

    if (safe_seq[0] != 1) {
        fprintf(stderr, "[FAIL] First process in safe sequence should be P1!\n");
        return 1;
    }
    printf("%s[PASS] Banker's Safety Test: Verified safe sequence starting with P1.%s\n",
           ANSI_GREEN, ANSI_RESET);

    /* Test Unsafe State Mutation (deplete available resources) */
    test_sys.avail[0] = 0;
    test_sys.avail[1] = 0;
    test_sys.avail[2] = 0;
    bool unsafe = is_system_safe(&test_sys, safe_seq, false);

    if (unsafe) {
        fprintf(stderr, "[FAIL] System with 0 available resources should be marked unsafe!\n");
        return 1;
    }
    printf("%s[PASS] Banker's Unsafe Detection Test: Successfully identified deadlock state.%s\n",
           ANSI_GREEN, ANSI_RESET);

    return 0;
}

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--test") == 0) {
        return run_deadlock_unit_test();
    }

    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);
    printf("%s            NEXADMIN - DEADLOCK & BANKER'S ALGORITHM SIMULATOR (C)            %s\n",
           ANSI_BOLD, ANSI_RESET);
    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);

    printf(" 1) Custom Interactive Allocation & Maximum Matrix Input\n");
    printf(" 2) Standard Academic Benchmark (Silberschatz 5 Processes, 3 Resource Types)\n");
    printf(" 3) Run Automated Self-Verification Unit Tests\n");
    int mode = read_int_bounded("Select Mode [1-3]: ", 1, 3);

    if (mode == 3) {
        return run_deadlock_unit_test();
    }

    SystemState sys;
    memset(&sys, 0, sizeof(sys));

    if (mode == 2) {
        sys.n = 5;
        sys.m = 3;

        int standard_alloc[5][3] = {
            {0, 1, 0},
            {2, 0, 0},
            {3, 0, 2},
            {2, 1, 1},
            {0, 0, 2}
        };
        int standard_max[5][3] = {
            {7, 5, 3},
            {3, 2, 2},
            {9, 0, 2},
            {2, 2, 2},
            {4, 3, 3}
        };
        int standard_avail[3] = {3, 3, 2};

        memcpy(sys.alloc, standard_alloc, sizeof(standard_alloc));
        memcpy(sys.max, standard_max, sizeof(standard_max));
        memcpy(sys.avail, standard_avail, sizeof(standard_avail));

        compute_need_matrix(&sys);
        printf("\n%s[LOADED BENCHMARK WORKLOAD]%s 5 Processes, 3 Resource Types (A, B, C).\n",
               ANSI_GREEN, ANSI_RESET);
    } else {
        sys.n = read_int_bounded("\nEnter number of processes (1-10): ", 1, 10);
        sys.m = read_int_bounded("Enter number of resource types (1-6): ", 1, 6);

        printf("\n--- Allocation Matrix (Current resources held by each process) ---\n");
        for (int i = 0; i < sys.n; i++) {
            printf("Process P%d:\n", i);
            for (int j = 0; j < sys.m; j++) {
                char p[64];
                snprintf(p, sizeof(p), "  Allocated units of Resource %c: ", 'A' + j);
                sys.alloc[i][j] = read_int_bounded(p, 0, 100);
            }
        }

        printf("\n--- Maximum Demand Matrix (Peak resources process may claim) ---\n");
        for (int i = 0; i < sys.n; i++) {
            printf("Process P%d:\n", i);
            for (int j = 0; j < sys.m; j++) {
                char p[64];
                snprintf(p, sizeof(p), "  Maximum units of Resource %c: ", 'A' + j);
                sys.max[i][j] = read_int_bounded(p, sys.alloc[i][j], 100);
            }
        }

        printf("\n--- Available Vector (Currently unallocated resources in system) ---\n");
        for (int j = 0; j < sys.m; j++) {
            char p[64];
            snprintf(p, sizeof(p), "Available units of Resource %c: ", 'A' + j);
            sys.avail[j] = read_int_bounded(p, 0, 100);
        }

        compute_need_matrix(&sys);
    }

    print_system_state(&sys);

    while (1) {
        printf("%sDeadlock Operations Menu:%s\n", ANSI_BOLD, ANSI_RESET);
        printf(" 1) Run Banker's Safety Algorithm (Check Safe/Unsafe & Find Safe Sequence)\n");
        printf(" 2) Simulate Dynamic Resource-Request Algorithm\n");
        printf(" 3) View Current Resource Allocation Matrices\n");
        printf(" 0) Exit Simulator\n");

        int choice = read_int_bounded("Choice [0-3]: ", 0, 3);
        if (choice == 0) break;

        switch (choice) {
            case 1: {
                int safe_seq[MAX_PROC];
                is_system_safe(&sys, safe_seq, true);
                break;
            }
            case 2:
                evaluate_resource_request(&sys);
                break;
            case 3:
                print_system_state(&sys);
                break;
            default:
                break;
        }
    }

    printf("\nExiting Deadlock Simulator.\n");
    return 0;
}
