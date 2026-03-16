#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

LOG_FILE=""
LOG_JOB=""
LOCK_FD=9
RSYNC_OPTS=()

log_line() {
    local level="$1"
    local event="$2"
    local details="${3:-}"
    local ts
    ts="$(date '+%F %T')"

    if [[ -n "$details" ]]; then
        printf '[%s] level=%s job=%s event=%s %s\n' "$ts" "$level" "$LOG_JOB" "$event" "$details" | tee -a "$LOG_FILE"
    else
        printf '[%s] level=%s job=%s event=%s\n' "$ts" "$level" "$LOG_JOB" "$event" | tee -a "$LOG_FILE"
    fi
}

log_info() {
    log_line "INFO" "$1" "${2:-}"
}

log_warn() {
    log_line "WARN" "$1" "${2:-}"
}

log_error() {
    log_line "ERROR" "$1" "${2:-}"
}

die() {
    log_error "fatal" "$*"
    exit 1
}

init_logging() {
    local file="$1"
    local job="$2"
    LOG_FILE="$file"
    LOG_JOB="$job"
    : >>"$LOG_FILE"
}

write_state() {
    local state_dir="$1"
    local key="$2"
    local value="$3"

    mkdir -p "$state_dir"
    printf '%s\n' "$value" >"$state_dir/$key"
}

snapshot_size_bytes() {
    local snapshot_dir="$1"

    if du -sb "$snapshot_dir" >/dev/null 2>&1; then
        du -sb "$snapshot_dir" | awk '{print $1}'
    else
        # BusyBox/macOS fallback when -b is not available.
        awk '{print $1 * 1024}' < <(du -sk "$snapshot_dir")
    fi
}

acquire_lock() {
    local lock_file="$1"

    mkdir -p "$(dirname "$lock_file")"
    eval "exec ${LOCK_FD}>\"$lock_file\""

    if ! flock -n "$LOCK_FD"; then
        die "Another backup instance is already running lock=$lock_file"
    fi

    log_info "lock.acquired" "file=$lock_file fd=$LOCK_FD"
}

set_backup_defaults() {
    : "${DEST_ROOT:=/backup-repo}"
    : "${DAILY_KEEP:=7}"
    : "${WEEKLY_KEEP:=4}"
    : "${MONTHLY_KEEP:=12}"
    : "${YEARLY_KEEP:=5}"
    : "${LOG_ROOT:=/var/log/backup-system}"
    : "${STATE_ROOT:=/var/lib/backup-state}"
    : "${RSYNC_SSH:=ssh -o BatchMode=yes}"
    : "${REQUIRE_MOUNT:=0}"
    : "${MIN_SNAPSHOT_SIZE_BYTES:=1}"
    : "${MIN_EXPECTED_ENTRIES:=1}"
    : "${DRY_RUN:=0}"

    if [[ -z "${EXCLUDE_FILE:-}" ]]; then
        EXCLUDE_FILE=""
    fi
}

validate_job_config() {
    [[ -n "${JOB_NAME:-}" ]] || die "Missing required JOB_NAME"
    [[ -n "${DEST_ROOT:-}" ]] || die "Missing required DEST_ROOT"

    if [[ -z "${BACKUP_PATHS+x}" ]]; then
        die "Missing required BACKUP_PATHS array"
    fi

    if (( ${#BACKUP_PATHS[@]} == 0 )); then
        die "BACKUP_PATHS must contain at least one path"
    fi

    local path
    for path in "${BACKUP_PATHS[@]}"; do
        [[ "$path" == /* ]] || die "BACKUP_PATHS must use absolute paths invalid=$path"
    done

    [[ "$DAILY_KEEP" =~ ^[0-9]+$ ]] || die "DAILY_KEEP must be numeric"
    [[ "$WEEKLY_KEEP" =~ ^[0-9]+$ ]] || die "WEEKLY_KEEP must be numeric"
    [[ "$MONTHLY_KEEP" =~ ^[0-9]+$ ]] || die "MONTHLY_KEEP must be numeric"
    [[ "$YEARLY_KEEP" =~ ^[0-9]+$ ]] || die "YEARLY_KEEP must be numeric"
    [[ "$REQUIRE_MOUNT" =~ ^[01]$ ]] || die "REQUIRE_MOUNT must be 0 or 1"
    [[ "$DRY_RUN" =~ ^[01]$ ]] || die "DRY_RUN must be 0 or 1"
    [[ "$MIN_SNAPSHOT_SIZE_BYTES" =~ ^[0-9]+$ ]] || die "MIN_SNAPSHOT_SIZE_BYTES must be numeric"
    [[ "$MIN_EXPECTED_ENTRIES" =~ ^[0-9]+$ ]] || die "MIN_EXPECTED_ENTRIES must be numeric"
}

require_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

preflight_checks() {
    require_command rsync
    require_command flock
    require_command find
    require_command sort

    mkdir -p "$DEST_ROOT" "$LOG_ROOT" "$STATE_ROOT"

    if (( REQUIRE_MOUNT == 1 )); then
        require_command mountpoint
        mountpoint -q "$DEST_ROOT" || die "Destination root is not a mounted filesystem: $DEST_ROOT"
    fi

    [[ -w "$DEST_ROOT" ]] || die "Destination root is not writable: $DEST_ROOT"

    # Test creating a test directory to ensure we can write
    if ! mkdir -p "$DEST_ROOT/.backup-test-dir" 2>/dev/null || ! rmdir "$DEST_ROOT/.backup-test-dir" 2>/dev/null; then
        die "Cannot create directories in destination root: $DEST_ROOT"
    fi
    [[ -w "$LOG_ROOT" ]] || die "Log root is not writable: $LOG_ROOT"
    [[ -w "$STATE_ROOT" ]] || die "State root is not writable: $STATE_ROOT"
}

snapshot_entry_count() {
    local snapshot_dir="$1"
    find "$snapshot_dir" -mindepth 1 | wc -l | awk '{print $1}'
}

validate_snapshot_integrity() {
    local snapshot_dir="$1"
    local size_bytes entry_count

    [[ -d "$snapshot_dir" ]] || die "Snapshot directory was not created: $snapshot_dir"

    size_bytes="$(snapshot_size_bytes "$snapshot_dir")"
    entry_count="$(snapshot_entry_count "$snapshot_dir")"

    if (( size_bytes < MIN_SNAPSHOT_SIZE_BYTES )); then
        die "Snapshot is smaller than expected size_bytes=$size_bytes min_bytes=$MIN_SNAPSHOT_SIZE_BYTES path=$snapshot_dir"
    fi

    if (( entry_count < MIN_EXPECTED_ENTRIES )); then
        die "Snapshot has fewer entries than expected entries=$entry_count min_entries=$MIN_EXPECTED_ENTRIES path=$snapshot_dir"
    fi

    log_info "snapshot.validated" "path=$snapshot_dir size_bytes=$size_bytes entries=$entry_count"
}

build_rsync_opts() {
    local source_host="$1"
    local previous_snapshot="$2"
    local ssh_cmd="$3"
    local exclude_file="$4"

    RSYNC_OPTS=(
        -aHAX
        --delete
        --numeric-ids
        --partial
        --stats
        --verbose
        --info=progress2
        --human-readable
    )

    if [[ -n "$source_host" ]]; then
        RSYNC_OPTS+=( -e "$ssh_cmd" )
    fi

    if [[ -n "$exclude_file" && -f "$exclude_file" ]]; then
        RSYNC_OPTS+=( --exclude-from="$exclude_file" )
    fi

    if (( DRY_RUN == 1 )); then
        RSYNC_OPTS+=( --dry-run )
    fi

    if [[ -n "$previous_snapshot" ]]; then
        RSYNC_OPTS+=( --link-dest="$previous_snapshot" )
        log_info "snapshot.previous" "path=$previous_snapshot"
    else
        log_info "snapshot.first" "No previous snapshot found"
    fi
}

create_daily_snapshot() {
    local source_host="$1"
    local final_snapshot="$2"
    local latest_link="$3"
    local ssh_cmd="$4"
    local exclude_file="$5"
    shift 5
    local backup_paths=("$@")

    local previous_snapshot=""
    local parent_dir tmp_snapshot source_spec path
    local completed=0  # Initialize here to avoid unbound variable errors

    if [[ -L "$latest_link" ]]; then
        previous_snapshot="$(readlink -f "$latest_link")"
    fi

    build_rsync_opts "$source_host" "$previous_snapshot" "$ssh_cmd" "$exclude_file"

    parent_dir="$(dirname "$final_snapshot")"
    tmp_snapshot="$parent_dir/.incomplete-$(basename "$final_snapshot")-$$"

    # Aggressive cleanup of ALL incomplete snapshots from previous runs
    printf '>>> Cleaning up leftover incomplete snapshots...\n' >&2
    find "$parent_dir" -maxdepth 1 -name ".incomplete-*" -type d 2>/dev/null | while read -r leftover; do
        printf 'Removing: %s\n' "$leftover" >&2
        rm -rf -- "$leftover" 2>/dev/null || true
    done
    printf '✓ Cleanup completed\n' >&2

    # Set up cleanup trap for interruptions - MUST be aggressive
    cleanup_incomplete() {
        if [[ -d "$tmp_snapshot" ]]; then
            printf '\n!!! Backup interrupted, forcing cleanup...\n' >&2
            # Force remove even if rsync is still writing
            rm -rf -- "$tmp_snapshot" 2>/dev/null || true
            sleep 1
            rm -rf -- "$tmp_snapshot" 2>/dev/null || true
        fi
    }
    trap cleanup_incomplete EXIT INT TERM HUP

    mkdir -p "$tmp_snapshot"
    log_info "snapshot.daily.start" "target=$final_snapshot tmp=$tmp_snapshot"

    # Verify destination is writable
    if ! touch "$tmp_snapshot/.backup-test" 2>/dev/null; then
        die "Cannot write to destination directory: $tmp_snapshot"
    fi
    rm -f "$tmp_snapshot/.backup-test"

    local total_paths=${#backup_paths[@]}
    local current_path=0

    for path in "${backup_paths[@]}"; do
        ((current_path++))
        printf '\n>>> [%d/%d] Starting backup for: %s\n' "$current_path" "$total_paths" "$path" >&2
        log_info "rsync.path.start" "path=$path progress=$current_path/$total_paths"

        if [[ -n "$source_host" ]]; then
            source_spec="${source_host}:${path}/"
        else
            source_spec="${path}/"
        fi

        # Create the full path structure in the snapshot directory
        if ! mkdir -p "$tmp_snapshot$path" 2>/dev/null; then
            log_warn "mkdir.failed" "path=$tmp_snapshot$path"
            continue
        fi

        # Run rsync - show output when running interactively
        if [[ -t 1 && -z "${INVOCATION_ID:-}" ]]; then
            printf '\n>>> Running rsync for %s...\n' "$path" >&2
            rsync "${RSYNC_OPTS[@]}" "$source_spec" "$tmp_snapshot$path/" || {
                local rsync_exit=$?
                log_error "rsync.failed" "path=$path exit_code=$rsync_exit"
                printf '⚠️  Rsync failed for %s, continuing with next path...\n' "$path" >&2
                continue
            }
        else
            rsync "${RSYNC_OPTS[@]}" "$source_spec" "$tmp_snapshot$path/" >&2 || {
                local rsync_exit=$?
                log_error "rsync.failed" "path=$path exit_code=$rsync_exit"
                printf '⚠️  Rsync failed for %s, continuing with next path...\n' "$path" >&2
                continue
            }
        fi

        printf '✓ Completed backup for: %s\n' "$path" >&2
        log_info "rsync.path.done" "path=$path progress=$current_path/$total_paths"
    done

    if (( DRY_RUN == 1 )); then
        rm -rf -- "$tmp_snapshot"
        completed=1
        printf '✓ DRY-RUN completed: %s\n' "$final_snapshot" >&2
        log_info "snapshot.daily.dry_run" "path=$final_snapshot"
        return 0
    fi

    mv "$tmp_snapshot" "$final_snapshot"
    completed=1
    printf '✓ Snapshot created successfully: %s\n' "$final_snapshot" >&2
    log_info "snapshot.daily.done" "path=$final_snapshot"
}

promote_snapshot() {
    local source_snapshot="$1"
    local target_snapshot="$2"

    if [[ -e "$target_snapshot" ]]; then
        log_warn "snapshot.promote.skip" "target_exists=$target_snapshot"
        return
    fi

    mkdir -p "$(dirname "$target_snapshot")"
    rsync -a --link-dest="$source_snapshot" "$source_snapshot/" "$target_snapshot/"
    log_info "snapshot.promote.done" "source=$source_snapshot target=$target_snapshot"
}

rotate_snapshots() {
    local tier_dir="$1"
    local keep_count="$2"

    [[ -d "$tier_dir" ]] || return 0

    mapfile -t snapshots < <(find "$tier_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

    local total="${#snapshots[@]}"
    if (( total <= keep_count )); then
        return 0
    fi

    local remove_count="$((total - keep_count))"
    local index old_path

    for ((index = 0; index < remove_count; index++)); do
        old_path="$tier_dir/${snapshots[$index]}"
        rm -rf -- "$old_path"
        log_info "snapshot.rotate.removed" "path=$old_path"
    done
}
