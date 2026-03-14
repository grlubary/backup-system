#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/backup-lib.sh
source "$REPO_ROOT/lib/backup-lib.sh"

usage() {
    cat <<'EOF'
Usage:
  backup-job.sh <job>
  backup-job.sh config/jobs/<job>.env
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

LOCK_FILE="/var/lock/backup-${JOB_NAME}.lock"
acquire_lock "$LOCK_FILE"

DATE_DAILY="$(date +%F)"
DATE_WEEKLY="$(date +%G-%V)"
DATE_MONTHLY="$(date +%Y-%m)"
DATE_YEARLY="$(date +%Y)"
DAY_OF_WEEK="$(date +%u)"
DAY_OF_MONTH="$(date +%d)"
MONTH_DAY="$(date +%m-%d)"
JOB_BASE="$DEST_ROOT/snapshots/$JOB_NAME"
DAILY_DIR="$JOB_BASE/daily"
WEEKLY_DIR="$JOB_BASE/weekly"
MONTHLY_DIR="$JOB_BASE/monthly"
YEARLY_DIR="$JOB_BASE/yearly"
LATEST_LINK="$DAILY_DIR/latest"
DAILY_SNAPSHOT="$DAILY_DIR/$DATE_DAILY"

STATE_DIR="$STATE_ROOT/$JOB_NAME"
LOG_DIR="$LOG_ROOT/$JOB_NAME"
LOG_FILE="$LOG_DIR/$DATE_DAILY.log"

mkdir -p "$DAILY_DIR" "$WEEKLY_DIR" "$MONTHLY_DIR" "$YEARLY_DIR" "$STATE_DIR" "$LOG_DIR"
init_logging "$LOG_FILE" "$JOB_NAME"

START_TS="$(date +%s)"
BACKUP_OK=0

on_exit() {
    local exit_code="$?"
    local end_ts duration run_ts

    end_ts="$(date +%s)"
    duration="$((end_ts - START_TS))"
    run_ts="$(date '+%F %T')"
    write_state "$STATE_DIR" "last_run" "$run_ts"
    write_state "$STATE_DIR" "last_duration" "$duration"

    if [[ "$BACKUP_OK" -eq 1 && "$exit_code" -eq 0 ]]; then
        write_state "$STATE_DIR" "last_success" "$run_ts"
        write_state "$STATE_DIR" "last_status" "OK"
        write_state "$STATE_DIR" "last_snapshot" "$DAILY_SNAPSHOT"
        write_state "$STATE_DIR" "last_size" "$(snapshot_size_bytes "$DAILY_SNAPSHOT")"
        log_info "backup.completed" "duration_sec=$duration snapshot=$DAILY_SNAPSHOT"
    else
        write_state "$STATE_DIR" "last_status" "ERROR"
        if [[ ! -f "$STATE_DIR/last_size" ]]; then
            write_state "$STATE_DIR" "last_size" "-1"
        fi
        if [[ ! -f "$STATE_DIR/last_snapshot" ]]; then
            write_state "$STATE_DIR" "last_snapshot" ""
        fi
        if [[ ! -f "$STATE_DIR/last_success" ]]; then
            write_state "$STATE_DIR" "last_success" ""
        fi
        log_error "backup.failed" "duration_sec=$duration exit_code=$exit_code"
    fi
}
trap on_exit EXIT

log_info "backup.started" "job=$JOB_NAME config=$JOB_FILE"

if [[ -e "$DAILY_SNAPSHOT" ]]; then
    die "Daily snapshot already exists: $DAILY_SNAPSHOT"
fi

create_daily_snapshot \
    "$SOURCE_HOST" \
    "$DAILY_SNAPSHOT" \
    "$LATEST_LINK" \
    "$RSYNC_SSH" \
    "$EXCLUDE_FILE" \
    "${BACKUP_PATHS[@]}"

ln -sfn "$DAILY_SNAPSHOT" "$LATEST_LINK"
log_info "snapshot.latest.updated" "path=$LATEST_LINK target=$DAILY_SNAPSHOT"

if [[ "$DAY_OF_WEEK" == "7" ]]; then
    promote_snapshot "$DAILY_SNAPSHOT" "$WEEKLY_DIR/$DATE_WEEKLY"
fi

if [[ "$DAY_OF_MONTH" == "01" ]]; then
    promote_snapshot "$DAILY_SNAPSHOT" "$MONTHLY_DIR/$DATE_MONTHLY"
fi

if [[ "$MONTH_DAY" == "01-01" ]]; then
    promote_snapshot "$DAILY_SNAPSHOT" "$YEARLY_DIR/$DATE_YEARLY"
fi

rotate_snapshots "$DAILY_DIR" "$DAILY_KEEP"
rotate_snapshots "$WEEKLY_DIR" "$WEEKLY_KEEP"
rotate_snapshots "$MONTHLY_DIR" "$MONTHLY_KEEP"
rotate_snapshots "$YEARLY_DIR" "$YEARLY_KEEP"

BACKUP_OK=1
exit 0
