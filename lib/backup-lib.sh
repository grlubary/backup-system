#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

LOG_FILE=""
LOG_JOB=""
LOCK_FD=9

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
    )

    if [[ -n "$source_host" ]]; then
        RSYNC_OPTS+=( -e "$ssh_cmd" )
    fi

    if [[ -n "$exclude_file" && -f "$exclude_file" ]]; then
        RSYNC_OPTS+=( --exclude-from="$exclude_file" )
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
    local completed=0

    if [[ -L "$latest_link" ]]; then
        previous_snapshot="$(readlink -f "$latest_link")"
    fi

    build_rsync_opts "$source_host" "$previous_snapshot" "$ssh_cmd" "$exclude_file"

    parent_dir="$(dirname "$final_snapshot")"
    tmp_snapshot="$parent_dir/.incomplete-$(basename "$final_snapshot")-$$"
    trap 'if (( completed == 0 )) && [[ -n "${tmp_snapshot:-}" && -d "$tmp_snapshot" ]]; then rm -rf -- "$tmp_snapshot"; fi' RETURN

    mkdir -p "$tmp_snapshot"
    log_info "snapshot.daily.start" "target=$final_snapshot tmp=$tmp_snapshot"

    for path in "${backup_paths[@]}"; do
        log_info "rsync.path.start" "path=$path"

        if [[ -n "$source_host" ]]; then
            source_spec="${source_host}:${path}/"
        else
            source_spec="${path}/"
        fi

        mkdir -p "$(dirname "$tmp_snapshot$path")"
        rsync "${RSYNC_OPTS[@]}" "$source_spec" "$tmp_snapshot$path/"

        log_info "rsync.path.done" "path=$path"
    done

    mv "$tmp_snapshot" "$final_snapshot"
    completed=1
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
