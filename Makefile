# ==============================================================================
# Makefile: NexAdmin C Engine & Academic OS Simulators
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# ==============================================================================

CC := gcc
CFLAGS := -Wall -Wextra -O2 -std=c11 -D_POSIX_C_SOURCE=200809L
SRC_DIR := src
BIN_DIR := bin

# Target executables
TARGETS := $(BIN_DIR)/scheduler $(BIN_DIR)/paging $(BIN_DIR)/deadlock

.PHONY: all clean test run help

# Default target: build all C executables
all: $(BIN_DIR) $(TARGETS)
	@echo "================================================================="
	@echo " NexAdmin C Simulators successfully built in $(BIN_DIR)/"
	@echo " Available binaries: scheduler, paging, deadlock"
	@echo " Run './nexadmin.sh' or 'make run' to launch the complete toolkit."
	@echo "================================================================="

# Create bin directory if absent
$(BIN_DIR):
	@mkdir -p $(BIN_DIR)

# Compilation rules
$(BIN_DIR)/scheduler: $(SRC_DIR)/scheduler.c | $(BIN_DIR)
	@echo "Compiling CPU Scheduling Simulator ($<)..."
	$(CC) $(CFLAGS) -o $@ $<

$(BIN_DIR)/paging: $(SRC_DIR)/paging.c | $(BIN_DIR)
	@echo "Compiling Page Replacement Simulator ($<)..."
	$(CC) $(CFLAGS) -o $@ $<

$(BIN_DIR)/deadlock: $(SRC_DIR)/deadlock.c | $(BIN_DIR)
	@echo "Compiling Deadlock / Banker's Algorithm Simulator ($<)..."
	$(CC) $(CFLAGS) -o $@ $<

# Test target: execute unit tests for all three C simulators and Bash syntax
test: all
	@echo ""
	@echo "================================================================="
	@echo " RUNNING NEXADMIN VERIFICATION TEST SUITE"
	@echo "================================================================="
	@echo "--- 1. Testing CPU Scheduler (FCFS, SJF, Round Robin) ---"
	@$(BIN_DIR)/scheduler --test
	@echo ""
	@echo "--- 2. Testing Page Replacement (FIFO, LRU, Optimal) ---"
	@$(BIN_DIR)/paging --test
	@echo ""
	@echo "--- 3. Testing Deadlock Avoidance (Banker's Algorithm) ---"
	@$(BIN_DIR)/deadlock --test
	@echo ""
	@echo "--- 4. Checking Bash Scripts Syntax (bash -n) ---"
	@bash -n nexadmin.sh lib/*.sh modules/*.sh
	@echo "[PASS] All Bash scripts syntax validated successfully."
	@echo ""
	@echo "================================================================="
	@echo " ALL UNIT TESTS & INTEGRATION AUDITS PASSED SUCCESSFULLY!"
	@echo "================================================================="

# Clean target: remove compiled binaries and temp files
clean:
	@echo "Cleaning compiled binaries..."
	@rm -rf $(BIN_DIR)/*
	@echo "Clean completed."

# Run target: build if necessary and launch NexAdmin
run: all
	@chmod +x nexadmin.sh
	@./nexadmin.sh

# Help target
help:
	@echo "NexAdmin Makefile Usage:"
	@echo "  make        Build all C simulators (bin/scheduler, bin/paging, bin/deadlock)"
	@echo "  make test   Execute unit tests for all C simulators and Bash scripts"
	@echo "  make clean  Remove compiled binaries"
	@echo "  make run    Build and launch NexAdmin toolkit"
