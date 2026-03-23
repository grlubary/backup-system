#!/usr/bin/env bash
set -Eeuo pipefail
trap 'printf "[ERROR] command failed: %s (line %s)\n" "${BASH_COMMAND}" "${LINENO}" >&2' ERR
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/backup-lib.sh
source "$REPO_ROOT/lib/backup-lib.sh"

usage() {
    cat <<'EOF'
Usage:
  seed-backup.sh <job>
  seed-backup.sh config/jobs/<job>.env

Creates or resumes the initial full snapshot as <date>.seeding.
It is intended for the first manual backup only.
EOF
}

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

JOB_ARG="$1"

if [[ "$JOB_ARG" == *.env || "$JOB_ARG" == */* ]]; then
    JOB_FILE="$JOB_ARG"
else
    JOB_FILE="$REPO_ROOT/config/jobs/$JOB_ARG.env"
fi

if [[ ! -f "$JOB_FILE" ]]; then
    printf 'Job config not found: %s\n' "$JOB_FILE" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$JOB_FILE"

set_backup_defaults
validate_job_config
preflight_checks

JOB_BASE="$DEST_ROOT/snapshots/$JOB_NAME"
DAILY_DIR="$JOB_BASE/daily"
LATEST_LINK="$DAILY_DIR/latest"
STATE_DIR="$STATE_ROOT/$JOB_NAME"
LOG_DIR="$LOG_ROOT/$JOB_NAME"
DATE_DAILY="$(date +%F)"
LOG_FILE="$LOG_DIR/seed-$DATE_DAILY.log"
LOCK_FILE="/var/lock/backup-${JOB_NAME}.lock"

mkdir -p "$DAILY_DIR" "$STATE_DIR" "$LOG_DIR"
init_logging "$LOG_FILE" "$JOB_NAME"
acquire_lock "$LOCK_FILE"

SEED_OK=0
SEED_MODE="resume"
SEED_SNAPSHOT=""
FINAL_SNAPSHOT=""
START_TS="$(date +%s)"

on_exit() {
    local exit_code="$?"
    local end_ts duration run_ts

    end_ts="$(date +%s)"
    duration="$((end_ts - START_TS))"
    run_ts="$(date '+%F %T')"

    write_state "$STATE_DIR" "last_run" "$run_ts"
    write_state "$STATE_DIR" "last_duration" "$duration"

    if [[ "$SEED_OK" -eq 1 && "$exit_code" -eq 0 ]]; then
        write_state "$STATE_DIR" "last_status" "OK"
        write_state "$STATE_DIR" "last_success" "$run_ts"
        write_state "$STATE_DIR" "last_snapshot" "$FINAL_SNAPSHOT"
        write_state "$STATE_DIR" "last_size" "$(snapshot_size_bytes "$FINAL_SNAPSHOT")"
        log_info "seed.completed" "duration_sec=$duration snapshot=$FINAL_SNAPSHOT mode=$SEED_MODE"
    elif [[ "$exit_code" -eq 130 ]]; then
        write_state "$STATE_DIR" "last_status" "INTERRUPTED"
        write_state "$STATE_DIR" "seed_snapshot" "$SEED_SNAPSHOT"
        log_warn "seed.interrupted" "duration_sec=$duration snapshot=$SEED_SNAPSHOT"
    else
        write_state "$STATE_DIR" "last_status" "ERROR"
        if [[ -n "$SEED_SNAPSHOT" ]]; then
            write_state "$STATE_DIR" "seed_snapshot" "$SEED_SNAPSHOT"
        fi
        log_error "seed.failed" "duration_sec=$duration exit_code=$exit_code snapshot=${SEED_SNAPSHOT:-unknown}"
    fi
}
trap on_exit EXIT

handle_interrupt() {
    log_warn "seed.signal" "signal=interrupt snapshot=$SEED_SNAPSHOT"
    printf '\nSeed interrupted. Resume later with the same command.\n' >&2
    exit 130
}
trap handle_interrupt INT TERM HUP

log_info "seed.started" "job=$JOB_NAME config=$JOB_FILE"

printf '\n==========================================\n' >&2
printf 'Starting Seed Backup: %s\n' "$JOB_NAME" >&2
printf '==========================================\n' >&2
printf 'Job Config: %s\n' "$JOB_FILE" >&2
printf 'Destination: %s\n' "$DEST_ROOT" >&2
printf 'Source Host: %s\n' "${SOURCE_HOST:-localhost}" >&2
printf 'Backup Paths: %s\n' "${#BACKUP_PATHS[@]}" >&2
printf 'Mode: Initial full backup with resume support\n' >&2
printf '\n' >&2

mapfile -t SEEDS < <(find "$DAILY_DIR" -maxdepth 1 -mindepth 1 -type d -name "*.seeding" | sort)

if (( ${#SEEDS[@]} > 1 )); then
    die "Multiple .seeding directories found; cleanup manually paths=${SEEDS[*]}"
fi

if (( ${#SEEDS[@]} == 1 )); then
    SEED_SNAPSHOT="${SEEDS[0]}"
    FINAL_SNAPSHOT="${SEED_SNAPSHOT%.seeding}"
    log_info "seed.resume" "seed=$SEED_SNAPSHOT final=$FINAL_SNAPSHOT"
    printf 'Resuming existing seed: %s\n' "$SEED_SNAPSHOT" >&2
else
    SEED_MODE="new"
    SEED_SNAPSHOT="$DAILY_DIR/$DATE_DAILY.seeding"
    FINAL_SNAPSHOT="$DAILY_DIR/$DATE_DAILY"

    if [[ -e "$FINAL_SNAPSHOT" ]]; then
        die "Final snapshot already exists: $FINAL_SNAPSHOT"
    fi

    mkdir -p "$SEED_SNAPSHOT"
    log_info "seed.create" "seed=$SEED_SNAPSHOT final=$FINAL_SNAPSHOT"
    printf 'Creating new seed: %s\n' "$SEED_SNAPSHOT" >&2
fi

write_state "$STATE_DIR" "last_status" "SEEDING"
write_state "$STATE_DIR" "seed_snapshot" "$SEED_SNAPSHOT"

build_rsync_opts "${SOURCE_HOST:-}" "$RSYNC_SSH" "$EXCLUDE_FILE"
RSYNC_BASE_OPTS=("${RSYNC_OPTS[@]}")
RSYNC_BASE_OPTS+=(
    --append-verify
    --timeout=14400
)

TOTAL_PATHS="${#BACKUP_PATHS[@]}"
CURRENT_PATH=0

for path in "${BACKUP_PATHS[@]}"; do
    ((CURRENT_PATH += 1))
    log_info "seed.path.start" "path=$path progress=$CURRENT_PATH/$TOTAL_PATHS"
    printf '\n>>> [%d/%d] Syncing: %s\n' "$CURRENT_PATH" "$TOTAL_PATHS" "$path" >&2

    if [[ -n "${SOURCE_HOST:-}" ]]; then
        SOURCE_SPEC="${SOURCE_HOST}:${path}/"
    else
        SOURCE_SPEC="${path}/"
    fi

    mkdir -p "$SEED_SNAPSHOT$path"
    rsync "${RSYNC_BASE_OPTS[@]}" "$SOURCE_SPEC" "$SEED_SNAPSHOT$path/"

    log_info "seed.path.done" "path=$path progress=$CURRENT_PATH/$TOTAL_PATHS"
    write_state "$STATE_DIR" "seed_last_path" "$path"
done

printf '\n>>> Validating seeded snapshot...\n' >&2
validate_snapshot_integrity "$SEED_SNAPSHOT"

mv "$SEED_SNAPSHOT" "$FINAL_SNAPSHOT"
ln -sfn "$FINAL_SNAPSHOT" "$LATEST_LINK"
rm -f "$STATE_DIR/seed_snapshot" "$STATE_DIR/seed_last_path"

printf '\n==========================================\n' >&2
printf '✓ Seed backup completed successfully!\n' >&2
printf '==========================================\n' >&2
printf 'Job: %s\n' "$JOB_NAME" >&2
printf 'Snapshot: %s\n' "$FINAL_SNAPSHOT" >&2
printf '==========================================\n' >&2

SEED_OK=1
exit 0
