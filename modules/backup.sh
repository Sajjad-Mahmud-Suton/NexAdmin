#!/usr/bin/env bash
# ==============================================================================
# File: modules/backup.sh
# Project: NexAdmin - Linux System Administration & Monitoring Toolkit
# Authors: University OS Lab Team
# Purpose: Enterprise Backup & Disaster Recovery Engine. Provides Full and
#          Incremental Tar/Gzip backups, cryptographic MD5 verification,
#          automated retention lifecycle pruning, and Crontab scheduling.
# ==============================================================================

BACKUP_DIR="${BASE_DIR}/backups"
DATA_DIR="${BASE_DIR}/data"

# Ensure backup destination directory exists
mkdir -p "${BACKUP_DIR}" "${DATA_DIR}"

# ==============================================================================
# Pre-Flight Storage Capacity Verification
# OS Concept: Storage quota and filesystem capacity planning before I/O operations
# ==============================================================================
check_disk_space_for_backup() {
    local source_dir="$1"
    local dest_dir="$2"

    # Estimate required space in KB
    local req_kb
    req_kb="$(du -sk "${source_dir}" 2>/dev/null | awk '{print $1}')"
    req_kb="${req_kb:-0}"

    # Get available space at destination in KB
    local avail_kb
    avail_kb="$(df -k "${dest_dir}" 2>/dev/null | tail -n 1 | awk '{print $4}')"
    avail_kb="${avail_kb:-0}"

    # Compressed tar.gz typically requires <= original size, but ensure 1.2x headroom
    local headroom_kb=$(( req_kb + 1024 ))

    if (( avail_kb < headroom_kb )); then
        printf "%s[INSUFFICIENT SPACE] Required: ~%d KB, Available: %d KB.%s\n" \
            "${COLOR_RED}" "${headroom_kb}" "${avail_kb}" "${COLOR_RESET}"
        return 1
    fi

    return 0
}

# ==============================================================================
# 1. Full Backup Implementation
# OS Concept: Archive generation (tar) and DEFLATE compression (gzip)
# ==============================================================================
create_full_backup() {
    local source_dir="$1"

    # Input validation
    if [[ ! -d "${source_dir}" ]]; then
        printf "%s[ERROR] Source directory '%s' does not exist!%s\n" "${COLOR_RED}" "${source_dir}" "${COLOR_RESET}"
        return 1
    fi

    if [[ ! -r "${source_dir}" ]]; then
        printf "%s[ERROR] Source directory '%s' is not readable!%s\n" "${COLOR_RED}" "${source_dir}" "${COLOR_RESET}"
        return 1
    fi

    if ! check_disk_space_for_backup "${source_dir}" "${BACKUP_DIR}"; then
        return 1
    fi

    local dir_basename
    dir_basename="$(basename "${source_dir}" | tr -cd 'A-Za-z0-9_-')"
    [[ -z "${dir_basename}" ]] && dir_basename="root"

    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local archive_filename="full_${dir_basename}_${timestamp}.tar.gz"
    local archive_path="${BACKUP_DIR}/${archive_filename}"
    local md5_path="${archive_path}.md5"
    local marker_file="${DATA_DIR}/.marker_${dir_basename}"

    printf "%sInitiating Full Backup of: %s%s\n" "${COLOR_CYAN}" "${source_dir}" "${COLOR_RESET}"
    printf "Destination Archive: %s\n" "${archive_path}"

    local parent_dir
    parent_dir="$(dirname "${source_dir}")"
    local target_folder
    target_folder="$(basename "${source_dir}")"

    # Archive without absolute path paths to ensure safe extraction
    if tar -czf "${archive_path}" -C "${parent_dir}" "${target_folder}" 2>/dev/null; then
        # Generate MD5 checksum
        (cd "${BACKUP_DIR}" && md5sum "${archive_filename}" > "${archive_filename}.md5")

        # Update incremental baseline marker
        touch "${marker_file}"

        local archive_size
        archive_size="$(du -h "${archive_path}" | awk '{print $1}')"

        log_action "Created full backup: ${archive_filename} (${archive_size})"
        printf "%s[SUCCESS] Full backup created successfully!%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
        printf "Archive Size : %s\n" "${archive_size}"
        printf "MD5 Checksum : %s\n" "$(awk '{print $1}' "${md5_path}")"
        return 0
    else
        log_action "FAILED full backup of: ${source_dir}"
        printf "%s[ERROR] Failed to create backup archive!%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        rm -f "${archive_path}" "${md5_path}" 2>/dev/null || true
        return 1
    fi
}

# ==============================================================================
# 2. Incremental Backup Implementation
# OS Concept: Differential file state tracking via inode modification timestamps (mtime)
# ==============================================================================
create_incremental_backup() {
    local source_dir="$1"

    if [[ ! -d "${source_dir}" ]]; then
        printf "%s[ERROR] Source directory '%s' does not exist!%s\n" "${COLOR_RED}" "${source_dir}" "${COLOR_RESET}"
        return 1
    fi

    local dir_basename
    dir_basename="$(basename "${source_dir}" | tr -cd 'A-Za-z0-9_-')"
    [[ -z "${dir_basename}" ]] && dir_basename="root"

    local marker_file="${DATA_DIR}/.marker_${dir_basename}"

    # If no marker exists, a baseline full backup must be taken first
    if [[ ! -f "${marker_file}" ]]; then
        printf "%s[NOTICE] No baseline marker found for '%s'. Initializing baseline Full Backup first...%s\n" \
            "${COLOR_YELLOW}" "${source_dir}" "${COLOR_RESET}"
        create_full_backup "${source_dir}"
        return $?
    fi

    # Find files modified newer than the marker
    local changed_files
    changed_files="$(find "${source_dir}" -newer "${marker_file}" -type f 2>/dev/null)"

    if [[ -z "${changed_files}" ]]; then
        printf "%s[NOTICE] No files modified since last backup. Incremental backup skipped.%s\n" \
            "${COLOR_GREEN}" "${COLOR_RESET}"
        return 0
    fi

    local count_changed
    count_changed="$(echo "${changed_files}" | wc -l | tr -d ' ')"
    printf "Detected %s modified/new file(s) since last backup.\n" "${count_changed}"

    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local archive_filename="inc_${dir_basename}_${timestamp}.tar.gz"
    local archive_path="${BACKUP_DIR}/${archive_filename}"
    local md5_path="${archive_path}.md5"

    local parent_dir
    parent_dir="$(dirname "${source_dir}")"
    local target_folder
    target_folder="$(basename "${source_dir}")"

    # Tar only files newer than marker
    if tar -czf "${archive_path}" -C "${parent_dir}" --newer-mtime="${marker_file}" "${target_folder}" 2>/dev/null; then
        (cd "${BACKUP_DIR}" && md5sum "${archive_filename}" > "${archive_filename}.md5")
        
        # Advance marker timestamp
        touch "${marker_file}"

        local archive_size
        archive_size="$(du -h "${archive_path}" | awk '{print $1}')"

        log_action "Created incremental backup: ${archive_filename} (${archive_size})"
        printf "%s[SUCCESS] Incremental backup completed successfully!%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
        printf "Archive Size : %s\n" "${archive_size}"
        printf "MD5 Checksum : %s\n" "$(awk '{print $1}' "${md5_path}")"
        return 0
    else
        log_action "FAILED incremental backup of: ${source_dir}"
        printf "%s[ERROR] Failed to generate incremental backup archive!%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        rm -f "${archive_path}" "${md5_path}" 2>/dev/null || true
        return 1
    fi
}

# ==============================================================================
# 3. Checksum Verification & Integrity Audit
# OS Concept: Cryptographic data integrity verification (MD5 hash collision resistance)
# ==============================================================================
verify_backup_integrity() {
    local archive_name="$1"
    local archive_path="${BACKUP_DIR}/${archive_name}"
    local md5_path="${archive_path}.md5"

    if [[ ! -f "${archive_path}" ]]; then
        printf "%s[ERROR] Archive file not found: %s%s\n" "${COLOR_RED}" "${archive_name}" "${COLOR_RESET}"
        return 1
    fi

    if [[ ! -f "${md5_path}" ]]; then
        printf "%s[WARNING] MD5 verification file missing for %s! Calculating new checksum...%s\n" \
            "${COLOR_YELLOW}" "${archive_name}" "${COLOR_RESET}"
        (cd "${BACKUP_DIR}" && md5sum "${archive_name}" > "${archive_name}.md5")
    fi

    printf "Verifying cryptographic MD5 checksum for: %s ... " "${archive_name}"
    if (cd "${BACKUP_DIR}" && md5sum -c "${archive_name}.md5" >/dev/null 2>&1); then
        printf "%s[PASS - INTEGRITY VERIFIED]%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
        return 0
    else
        printf "%s[FAILED - CORRUPTED OR TAMPERED]%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        log_action "SECURITY AUDIT FAILURE: Checksum mismatch for ${archive_name}!"
        return 1
    fi
}

# ==============================================================================
# 4. Backup Catalog Listing
# ==============================================================================
list_backups() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                           NEXADMIN - BACKUP CATALOG                            %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    
    local backups_found
    backups_found="$(find "${BACKUP_DIR}" -maxdepth 1 -name '*.tar.gz' 2>/dev/null | sort -r)"

    if [[ -z "${backups_found}" ]]; then
        printf "%sNo backup archives currently available in %s%s\n\n" "${COLOR_DIM}" "${BACKUP_DIR}" "${COLOR_RESET}"
        return 1
    fi

    printf "%-5s %-32s %-8s %-10s %-18s\n" "NUM" "ARCHIVE FILENAME" "TYPE" "SIZE" "CREATED DATE"
    printf "%s\n" "--------------------------------------------------------------------------------"

    local idx=1
    while read -r bpath; do
        [[ -z "${bpath}" ]] && continue
        local bname
        bname="$(basename "${bpath}")"
        local btype="Full"
        [[ "${bname}" =~ ^inc_ ]] && btype="Incr"
        local bsize
        bsize="$(du -h "${bpath}" 2>/dev/null | awk '{print $1}')"
        local bdate
        bdate="$(date -r "${bpath}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "Unknown")"

        printf "%-5d %-32s %-8s %-10s %-18s\n" "${idx}" "${bname:0:32}" "${btype}" "${bsize}" "${bdate}"
        (( idx++ ))
    done <<< "${backups_found}"

    printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    return 0
}

# ==============================================================================
# 5. Restore Backup Archive
# OS Concept: Non-destructive restoration with strict target isolation
# ==============================================================================
restore_backup_archive() {
    if ! list_backups; then
        pause_screen
        return 1
    fi

    # Read archive selection
    local backups_array=()
    while IFS= read -r bpath; do
        [[ -n "${bpath}" ]] && backups_array+=("$(basename "${bpath}")")
    done < <(find "${BACKUP_DIR}" -maxdepth 1 -name '*.tar.gz' 2>/dev/null | sort -r)

    local total_count="${#backups_array[@]}"
    printf "\nEnter backup number to restore [1-%d] (or 0 to cancel): " "${total_count}"
    read -r sel_num

    if ! is_number "${sel_num}" || (( sel_num < 1 || sel_num > total_count )); then
        printf "%sRestoration cancelled or invalid selection.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        sleep 1
        return 0
    fi

    local selected_archive="${backups_array[$(( sel_num - 1 ))]}"
    local archive_path="${BACKUP_DIR}/${selected_archive}"

    # Step 1: Pre-Restoration Checksum Audit
    printf "\n%s[STEP 1: CRYPTOGRAPHIC INTEGRITY CHECK]%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
    if ! verify_backup_integrity "${selected_archive}"; then
        printf "%s[CRITICAL ERROR] Archive failed integrity verification! Restoration aborted to prevent corruption.%s\n" \
            "${COLOR_RED}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    # Step 2: Destination directory selection
    printf "\n%s[STEP 2: TARGET EXTRACTION DIRECTORY]%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
    printf "Enter absolute destination directory for extraction (e.g., /tmp/restore_test): "
    read -r target_dest

    if [[ -z "${target_dest}" ]]; then
        printf "%s[ERROR] Target directory cannot be empty.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    # Ensure target directory exists and is writable
    mkdir -p "${target_dest}" 2>/dev/null
    if [[ ! -w "${target_dest}" ]]; then
        printf "%s[ERROR] Target directory '%s' is not writable!%s\n" "${COLOR_RED}" "${target_dest}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    # Step 3: Confirmation
    printf "\n%sSelected Archive: %s%s\n" "${COLOR_CYAN}" "${selected_archive}" "${COLOR_RESET}"
    printf "%sTarget Location : %s%s\n" "${COLOR_CYAN}" "${target_dest}" "${COLOR_RESET}"
    if ! confirm "Proceed with restoring files into target directory?"; then
        printf "%sRestoration cancelled by user.%s\n" "${COLOR_YELLOW}" "${COLOR_RESET}"
        pause_screen
        return 0
    fi

    # Step 4: Secure Extraction
    # Safety: tar -xzf into target directory (-C) without absolute outside references
    printf "Extracting archive contents...\n"
    if tar -xzf "${archive_path}" -C "${target_dest}" 2>/dev/null; then
        log_action "Restored backup ${selected_archive} into ${target_dest}"
        printf "%s[SUCCESS] Archive restored successfully into %s!%s\n" "${COLOR_GREEN}" "${target_dest}" "${COLOR_RESET}"
    else
        log_action "FAILED to restore backup ${selected_archive}"
        printf "%s[ERROR] Archive extraction encountered errors.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
    fi

    pause_screen
}

# ==============================================================================
# 6. Retention Lifecycle Pruner
# OS Concept: Automatic disk space reclamation and TTL (Time-To-Live) management
# ==============================================================================
prune_old_backups() {
    local retention_days="${BACKUP_RETENTION_DAYS:-7}"

    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                   NEXADMIN - BACKUP RETENTION LIFECYCLE                        %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "Configured Retention Window: %s%s days%s\n\n" "${COLOR_BOLD}" "${retention_days}" "${COLOR_RESET}"

    local old_files
    old_files="$(find "${BACKUP_DIR}" -maxdepth 1 -name '*.tar.gz' -mtime "+${retention_days}" 2>/dev/null)"

    if [[ -z "${old_files}" ]]; then
        printf "%s[OK] No backups older than %s days were found.%s\n\n" "${COLOR_GREEN}" "${retention_days}" "${COLOR_RESET}"
        pause_screen
        return 0
    fi

    printf "%sThe following archives exceed the %s-day retention threshold:%s\n\n" "${COLOR_YELLOW}" "${retention_days}" "${COLOR_RESET}"
    echo "${old_files}" | while read -r f; do
        local fsize fdate
        fsize="$(du -h "${f}" 2>/dev/null | awk '{print $1}')"
        fdate="$(date -r "${f}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "Unknown")"
        printf " - %s (%s, Modified: %s)\n" "$(basename "${f}")" "${fsize}" "${fdate}"
    done

    printf "\n"
    if confirm "Delete these expired archives and their MD5 checksums?" "n"; then
        echo "${old_files}" | while read -r f; do
            rm -f "${f}" "${f}.md5" 2>/dev/null || true
            log_action "Pruned expired backup: $(basename "${f}")"
        done
        printf "%s[SUCCESS] Expired backups purged successfully.%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
    else
        printf "%sPurge cancelled. No files were modified.%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
    fi

    pause_screen
}

# ==============================================================================
# 7. Crontab Automated Backup Scheduling
# OS Concept: Vixie cron daemon job configuration and crontab automation
# ==============================================================================
schedule_backup_cron() {
    clear
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s                    AUTOMATED CRON BACKUP SCHEDULING                            %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
    printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"

    local target_dir="${DEFAULT_BACKUP_DIR:-/tmp/nexadmin_demo}"
    printf "Enter directory to schedule for automated daily backup [%s]: " "${target_dir}"
    read -r user_dir
    target_dir="${user_dir:-${target_dir}}"

    if [[ ! -d "${target_dir}" ]]; then
        printf "%s[ERROR] Directory '%s' does not exist!%s\n" "${COLOR_RED}" "${target_dir}" "${COLOR_RESET}"
        pause_screen
        return 1
    fi

    local backup_cmd="${BASE_DIR}/modules/backup.sh"
    # Create an independent CLI-callable wrapper if invoked directly by cron
    local cron_comment="# NexAdmin Automated Daily Backup for ${target_dir}"
    local cron_job="0 2 * * * /bin/bash -c 'source \"${BASE_DIR}/lib/common.sh\" && source \"${BASE_DIR}/modules/backup.sh\" && create_incremental_backup \"${target_dir}\"' >/dev/null 2>&1"

    printf "\n%sProposed Crontab Entry (Runs daily at 02:00 AM):%s\n" "${COLOR_BOLD}" "${COLOR_RESET}"
    printf "%s%s%s\n" "${COLOR_YELLOW}" "${cron_comment}" "${COLOR_RESET}"
    printf "%s%s%s\n\n" "${COLOR_CYAN}" "${cron_job}" "${COLOR_RESET}"

    # Check existing crontab
    local current_crontab
    current_crontab="$(crontab -l 2>/dev/null || true)"

    if echo "${current_crontab}" | grep -q "NexAdmin Automated Daily Backup for ${target_dir}"; then
        printf "%s[NOTICE] An automated backup schedule for this directory already exists in crontab.%s\n" \
            "${COLOR_YELLOW}" "${COLOR_RESET}"
    else
        if confirm "Would you like to install this entry into your user crontab?"; then
            (
                echo "${current_crontab}"
                echo "${cron_comment}"
                echo "${cron_job}"
            ) | grep -v '^$' | crontab -
            log_action "Scheduled crontab backup for ${target_dir}"
            printf "%s[SUCCESS] Backup schedule successfully installed into crontab!%s\n" "${COLOR_GREEN}" "${COLOR_RESET}"
        fi
    fi

    pause_screen
}

# ==============================================================================
# Backup & Restore Interactive Menu
# ==============================================================================
menu_backup_restore() {
    log_action "Accessed Backup & Restore Manager"
    local b_choice=""

    while true; do
        clear
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s                 NEXADMIN - BACKUP & DISASTER RECOVERY MANAGER                  %s\n" "${COLOR_BOLD}${COLOR_CYAN}" "${COLOR_RESET}"
        printf "%s================================================================================%s\n" "${COLOR_CYAN}" "${COLOR_RESET}"
        printf " Backup Storage Directory: %s%s%s\n" "${COLOR_BOLD}" "${BACKUP_DIR}" "${COLOR_RESET}"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "  1) Create Full Backup (tar.gz + MD5)\n"
        printf "  2) Create Incremental Backup (only modified/new files)\n"
        printf "  3) List Available Backups\n"
        printf "  4) Verify Archive MD5 Integrity\n"
        printf "  5) Restore Backup Archive\n"
        printf "  6) Prune Expired Backups (Retention Policy: %s days)\n" "${BACKUP_RETENTION_DAYS:-7}"
        printf "  7) Schedule Automated Daily Backup (Crontab)\n"
        printf "  0) Back to Main Menu\n"
        printf "%s--------------------------------------------------------------------------------%s\n" "${COLOR_DIM}" "${COLOR_RESET}"
        printf "Enter choice [0-7]: "
        read -r b_choice

        case "${b_choice}" in
            1)
                printf "\nEnter source directory path to backup [%s]: " "${DEFAULT_BACKUP_DIR:-/tmp/nexadmin_demo}"
                read -r s_dir
                s_dir="${s_dir:-${DEFAULT_BACKUP_DIR:-/tmp/nexadmin_demo}}"
                create_full_backup "${s_dir}"
                pause_screen
                ;;
            2)
                printf "\nEnter source directory path for incremental backup [%s]: " "${DEFAULT_BACKUP_DIR:-/tmp/nexadmin_demo}"
                read -r s_dir
                s_dir="${s_dir:-${DEFAULT_BACKUP_DIR:-/tmp/nexadmin_demo}}"
                create_incremental_backup "${s_dir}"
                pause_screen
                ;;
            3)
                list_backups
                pause_screen
                ;;
            4)
                if list_backups; then
                    printf "\nEnter exact archive filename to verify: "
                    read -r a_name
                    if [[ -n "${a_name}" ]]; then
                        verify_backup_integrity "${a_name}"
                    fi
                fi
                pause_screen
                ;;
            5)
                restore_backup_archive
                ;;
            6)
                prune_old_backups
                ;;
            7)
                schedule_backup_cron
                ;;
            0)
                break
                ;;
            *)
                printf "%sInvalid choice! Please choose 0-7.%s\n" "${COLOR_RED}" "${COLOR_RESET}"
                sleep 1
                ;;
        esac
    done
}
