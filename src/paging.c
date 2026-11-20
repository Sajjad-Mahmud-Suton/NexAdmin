/*
 * ==============================================================================
 * File: src/paging.c
 * Project: NexAdmin - Linux System Administration & Monitoring Toolkit
 * Authors: University OS Lab Team
 * Purpose: Virtual Memory Page Replacement Simulator in C. Implements FIFO, LRU,
 *          and Optimal (Belady's MIN) algorithms with a step-by-step frame table,
 *          hit/fault tracking, and ratio analytics.
 * ==============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define MAX_FRAMES 16
#define MAX_PAGES  128

/* ANSI Color Escape Codes */
#define ANSI_CYAN    "\033[0;36m"
#define ANSI_GREEN   "\033[0;32m"
#define ANSI_YELLOW  "\033[0;33m"
#define ANSI_RED     "\033[0;31m"
#define ANSI_BOLD    "\033[1m"
#define ANSI_RESET   "\033[0m"

typedef struct {
    int page_faults;
    int page_hits;
    double fault_ratio;
    double hit_ratio;
} PagingStats;

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
 * Prints step-by-step memory frame allocation trace table header.
 */
static void print_trace_header(int num_frames) {
    printf("\n%-6s | %-6s | ", "STEP", "PAGE");
    for (int f = 0; f < num_frames; f++) {
        printf("FRAME %-2d | ", f + 1);
    }
    printf("%-8s\n", "STATUS");
    printf("-------+--------+");
    for (int f = 0; f < num_frames; f++) {
        printf("-----------+");
    }
    printf("----------\n");
}

/*
 * Prints a single step in the memory trace table.
 */
static void print_trace_step(int step, int page, const int frames[], int num_frames, bool hit) {
    printf("%-6d | %-6d | ", step + 1, page);
    for (int f = 0; f < num_frames; f++) {
        if (frames[f] == -1) {
            printf("%-10s | ", "-");
        } else {
            printf("%-10d | ", frames[f]);
        }
    }
    if (hit) {
        printf("%s%-8s%s\n", ANSI_GREEN, "HIT", ANSI_RESET);
    } else {
        printf("%s%-8s%s\n", ANSI_RED, "FAULT", ANSI_RESET);
    }
}

/*
 * Prints summary statistics (Hits, Faults, Hit Ratio, Fault Ratio).
 */
static void print_paging_summary(const char *algo_name, const PagingStats *stats, int total_refs) {
    printf("\n%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);
    printf(" Page Replacement Algorithm : %s%s%s\n", ANSI_BOLD, algo_name, ANSI_RESET);
    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);
    printf(" Total Page References : %s%d%s\n", ANSI_BOLD, total_refs, ANSI_RESET);
    printf(" Total Page Hits       : %s%d%s\n", ANSI_GREEN, stats->page_hits, ANSI_RESET);
    printf(" Total Page Faults     : %s%d%s\n", ANSI_RED, stats->page_faults, ANSI_RESET);
    printf(" Hit Ratio             : %s%.2f%%%s (Hits / Total * 100)\n",
           ANSI_GREEN, stats->hit_ratio, ANSI_RESET);
    printf(" Fault Ratio           : %s%.2f%%%s (Faults / Total * 100)\n",
           ANSI_RED, stats->fault_ratio, ANSI_RESET);
    printf("%s================================================================================%s\n\n",
           ANSI_CYAN, ANSI_RESET);
}

/*
 * 1. First-In, First-Out (FIFO) Page Replacement
 * OS Concept: Replaces the oldest page brought into physical memory.
 *             Susceptible to Belady's Anomaly where allocating more physical frames
 *             can counter-intuitively result in more page faults.
 */
PagingStats simulate_fifo(const int pages[], int n, int num_frames, bool verbose) {
    int frames[MAX_FRAMES];
    for (int i = 0; i < num_frames; i++) frames[i] = -1;

    int fifo_ptr = 0;
    int faults = 0;
    int hits = 0;

    if (verbose) print_trace_header(num_frames);

    for (int i = 0; i < n; i++) {
        int current_page = pages[i];
        bool is_hit = false;

        /* Check if page already resides in one of the frames */
        for (int f = 0; f < num_frames; f++) {
            if (frames[f] == current_page) {
                is_hit = true;
                break;
            }
        }

        if (is_hit) {
            hits++;
        } else {
            faults++;
            /* Replace page at the circular FIFO pointer position */
            frames[fifo_ptr] = current_page;
            fifo_ptr = (fifo_ptr + 1) % num_frames;
        }

        if (verbose) {
            print_trace_step(i, current_page, frames, num_frames, is_hit);
        }
    }

    PagingStats stats = {
        .page_faults = faults,
        .page_hits = hits,
        .fault_ratio = ((double)faults / (double)n) * 100.0,
        .hit_ratio = ((double)hits / (double)n) * 100.0
    };

    if (verbose) {
        print_paging_summary("First-In, First-Out (FIFO)", &stats, n);
    }
    return stats;
}

/*
 * 2. Least Recently Used (LRU) Page Replacement
 * OS Concept: Replaces the page that has not been referenced for the longest duration.
 *             Approximates optimal replacement by utilizing the principle of temporal locality.
 *             Belongs to the class of stack algorithms (immune to Belady's Anomaly).
 */
PagingStats simulate_lru(const int pages[], int n, int num_frames, bool verbose) {
    int frames[MAX_FRAMES];
    int last_used[MAX_FRAMES];
    for (int i = 0; i < num_frames; i++) {
        frames[i] = -1;
        last_used[i] = -1;
    }

    int faults = 0;
    int hits = 0;

    if (verbose) print_trace_header(num_frames);

    for (int i = 0; i < n; i++) {
        int current_page = pages[i];
        bool is_hit = false;
        int hit_frame = -1;

        for (int f = 0; f < num_frames; f++) {
            if (frames[f] == current_page) {
                is_hit = true;
                hit_frame = f;
                break;
            }
        }

        if (is_hit) {
            hits++;
            last_used[hit_frame] = i; /* Update access timestamp */
        } else {
            faults++;
            /* Check if there is an empty frame first */
            int target_frame = -1;
            for (int f = 0; f < num_frames; f++) {
                if (frames[f] == -1) {
                    target_frame = f;
                    break;
                }
            }

            /* If all frames full, evict frame with minimum last_used timestamp */
            if (target_frame == -1) {
                int min_time = 1e9;
                for (int f = 0; f < num_frames; f++) {
                    if (last_used[f] < min_time) {
                        min_time = last_used[f];
                        target_frame = f;
                    }
                }
            }

            frames[target_frame] = current_page;
            last_used[target_frame] = i;
        }

        if (verbose) {
            print_trace_step(i, current_page, frames, num_frames, is_hit);
        }
    }

    PagingStats stats = {
        .page_faults = faults,
        .page_hits = hits,
        .fault_ratio = ((double)faults / (double)n) * 100.0,
        .hit_ratio = ((double)hits / (double)n) * 100.0
    };

    if (verbose) {
        print_paging_summary("Least Recently Used (LRU)", &stats, n);
    }
    return stats;
}

/*
 * 3. Optimal (Belady's MIN) Page Replacement
 * OS Concept: Replaces the page that will not be referenced for the longest period in the future.
 *             Theoretical offline algorithm that achieves the provable minimum page fault rate.
 *             Used as a gold standard to evaluate the efficiency of online algorithms like LRU.
 */
PagingStats simulate_optimal(const int pages[], int n, int num_frames, bool verbose) {
    int frames[MAX_FRAMES];
    for (int i = 0; i < num_frames; i++) frames[i] = -1;

    int faults = 0;
    int hits = 0;

    if (verbose) print_trace_header(num_frames);

    for (int i = 0; i < n; i++) {
        int current_page = pages[i];
        bool is_hit = false;

        for (int f = 0; f < num_frames; f++) {
            if (frames[f] == current_page) {
                is_hit = true;
                break;
            }
        }

        if (is_hit) {
            hits++;
        } else {
            faults++;
            int target_frame = -1;

            /* Check for empty frame first */
            for (int f = 0; f < num_frames; f++) {
                if (frames[f] == -1) {
                    target_frame = f;
                    break;
                }
            }

            /* Look forward into future reference stream to find optimal candidate */
            if (target_frame == -1) {
                int farthest_use = -1;

                for (int f = 0; f < num_frames; f++) {
                    int next_use = -1;
                    for (int future = i + 1; future < n; future++) {
                        if (pages[future] == frames[f]) {
                            next_use = future;
                            break;
                        }
                    }

                    /* If page is never referenced again, it is the ideal candidate */
                    if (next_use == -1) {
                        target_frame = f;
                        break;
                    }

                    if (next_use > farthest_use) {
                        farthest_use = next_use;
                        target_frame = f;
                    }
                }
            }

            frames[target_frame] = current_page;
        }

        if (verbose) {
            print_trace_step(i, current_page, frames, num_frames, is_hit);
        }
    }

    PagingStats stats = {
        .page_faults = faults,
        .page_hits = hits,
        .fault_ratio = ((double)faults / (double)n) * 100.0,
        .hit_ratio = ((double)hits / (double)n) * 100.0
    };

    if (verbose) {
        print_paging_summary("Belady's Optimal (OPT)", &stats, n);
    }
    return stats;
}

/*
 * Automated unit test suite verifying against standard operating systems textbook benchmarks.
 */
int run_paging_unit_test(void) {
    printf("[UNIT TEST] Running Page Replacement Algorithms Verification...\n");

    /* Classic Silberschatz OS Textbook Reference String (20 references):
     * 7, 0, 1, 2, 0, 3, 0, 4, 2, 3, 0, 3, 2, 1, 2, 0, 1, 7, 0, 1
     * Frame Count: 3
     * Theoretical Results:
     * - FIFO:    15 Page Faults, 5 Hits
     * - LRU:     12 Page Faults, 8 Hits
     * - Optimal:  9 Page Faults, 11 Hits
     */
    const int benchmark_pages[] = {
        7, 0, 1, 2, 0, 3, 0, 4, 2, 3, 0, 3, 2, 1, 2, 0, 1, 7, 0, 1
    };
    int n = 20;
    int frames = 3;

    /* 1. Verify FIFO */
    PagingStats fifo_res = simulate_fifo(benchmark_pages, n, frames, false);
    if (fifo_res.page_faults != 15 || fifo_res.page_hits != 5) {
        fprintf(stderr, "[FAIL] FIFO benchmark failed: Expected 15 faults / 5 hits, got %d / %d\n",
                fifo_res.page_faults, fifo_res.page_hits);
        return 1;
    }
    printf("%s[PASS] FIFO Benchmark: Exactly 15 Faults and 5 Hits verified.%s\n",
           ANSI_GREEN, ANSI_RESET);

    /* 2. Verify LRU */
    PagingStats lru_res = simulate_lru(benchmark_pages, n, frames, false);
    if (lru_res.page_faults != 12 || lru_res.page_hits != 8) {
        fprintf(stderr, "[FAIL] LRU benchmark failed: Expected 12 faults / 8 hits, got %d / %d\n",
                lru_res.page_faults, lru_res.page_hits);
        return 1;
    }
    printf("%s[PASS] LRU Benchmark: Exactly 12 Faults and 8 Hits verified.%s\n",
           ANSI_GREEN, ANSI_RESET);

    /* 3. Verify Optimal */
    PagingStats opt_res = simulate_optimal(benchmark_pages, n, frames, false);
    if (opt_res.page_faults != 9 || opt_res.page_hits != 11) {
        fprintf(stderr, "[FAIL] Optimal benchmark failed: Expected 9 faults / 11 hits, got %d / %d\n",
                opt_res.page_faults, opt_res.page_hits);
        return 1;
    }
    printf("%s[PASS] Optimal Benchmark: Exactly 9 Faults and 11 Hits verified.%s\n",
           ANSI_GREEN, ANSI_RESET);

    return 0;
}

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "--test") == 0) {
        return run_paging_unit_test();
    }

    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);
    printf("%s               NEXADMIN - PAGE REPLACEMENT SIMULATOR (C ENGINE)               %s\n",
           ANSI_BOLD, ANSI_RESET);
    printf("%s================================================================================%s\n",
           ANSI_CYAN, ANSI_RESET);

    printf(" 1) Custom Interactive Reference String\n");
    printf(" 2) Standard Academic Benchmark (Silberschatz 20-Page String, 3 Frames)\n");
    printf(" 3) Run Automated Self-Verification Unit Tests\n");
    int mode = read_int_bounded("Select Mode [1-3]: ", 1, 3);

    if (mode == 3) {
        return run_paging_unit_test();
    }

    int pages[MAX_PAGES];
    int n = 0;
    int num_frames = 0;

    if (mode == 2) {
        const int benchmark[] = {
            7, 0, 1, 2, 0, 3, 0, 4, 2, 3, 0, 3, 2, 1, 2, 0, 1, 7, 0, 1
        };
        n = 20;
        memcpy(pages, benchmark, sizeof(benchmark));
        num_frames = 3;

        printf("\n%s[LOADED BENCHMARK REFERENCE STRING]%s\n", ANSI_GREEN, ANSI_RESET);
        printf(" Reference String : 7 0 1 2 0 3 0 4 2 3 0 3 2 1 2 0 1 7 0 1\n");
        printf(" Physical Frames  : 3\n\n");
    } else {
        num_frames = read_int_bounded("\nEnter number of physical page frames (1-8): ", 1, 8);
        n = read_int_bounded("Enter total number of page references (1-64): ", 1, 64);

        printf("\nEnter %d page numbers separated by spaces (e.g. 7 0 1 2 ...):\n", n);
        for (int i = 0; i < n; i++) {
            while (scanf("%d", &pages[i]) != 1 || pages[i] < 0) {
                printf("%s[ERROR] Please enter a valid non-negative page number: %s", ANSI_RED, ANSI_RESET);
                clear_input_buffer();
            }
        }
        clear_input_buffer();
    }

    while (1) {
        printf("\n%sSelect Page Replacement Algorithm:%s\n", ANSI_BOLD, ANSI_RESET);
        printf(" 1) First-In, First-Out (FIFO)\n");
        printf(" 2) Least Recently Used (LRU)\n");
        printf(" 3) Belady's Optimal (OPT)\n");
        printf(" 4) Comparative Multi-Algorithm Benchmark\n");
        printf(" 0) Exit Simulator\n");

        int choice = read_int_bounded("Choice [0-4]: ", 0, 4);
        if (choice == 0) break;

        switch (choice) {
            case 1:
                simulate_fifo(pages, n, num_frames, true);
                break;
            case 2:
                simulate_lru(pages, n, num_frames, true);
                break;
            case 3:
                simulate_optimal(pages, n, num_frames, true);
                break;
            case 4: {
                printf("\n>>> 1. FIRST-IN, FIRST-OUT (FIFO) <<<\n");
                PagingStats s1 = simulate_fifo(pages, n, num_frames, true);
                printf("\n>>> 2. LEAST RECENTLY USED (LRU) <<<\n");
                PagingStats s2 = simulate_lru(pages, n, num_frames, true);
                printf("\n>>> 3. BELADY'S OPTIMAL (OPT) <<<\n");
                PagingStats s3 = simulate_optimal(pages, n, num_frames, true);

                printf("\n%s================ COMPARATIVE EFFICIENCY SUMMARY ===============%s\n",
                       ANSI_BOLD, ANSI_RESET);
                printf("%-15s | %-12s | %-12s | %-12s\n", "ALGORITHM", "PAGE FAULTS", "PAGE HITS", "HIT RATIO");
                printf("----------------+--------------+--------------+-------------\n");
                printf("%-15s | %-12d | %-12d | %-11.2f%%\n", "FIFO", s1.page_faults, s1.page_hits, s1.hit_ratio);
                printf("%-15s | %-12d | %-12d | %-11.2f%%\n", "LRU", s2.page_faults, s2.page_hits, s2.hit_ratio);
                printf("%-15s | %-12d | %-12d | %-11.2f%%\n", "OPTIMAL", s3.page_faults, s3.page_hits, s3.hit_ratio);
                printf("%s================================================================%s\n",
                       ANSI_BOLD, ANSI_RESET);
                break;
            }
            default:
                break;
        }
    }

    printf("\nExiting Page Replacement Simulator.\n");
    return 0;
}
