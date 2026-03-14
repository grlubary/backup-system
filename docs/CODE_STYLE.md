# CODE_STYLE.md

Coding standards for the backup-system project.

Language:

Bash

All scripts must follow these rules.

Shell safety:

Always start scripts with:

set -Eeuo pipefail
IFS=$'\n\t'

Error handling:

Scripts must fail fast when errors occur.

Never ignore command failures.

Logging:

Use structured logging with timestamps.

Example:

log() {
    echo "[$(date '+%F %T')] $*"
}

Locking:

Backup scripts must prevent concurrent execution using:

flock

Example:

exec 9>/var/lock/backup.lock
flock -n 9

Rsync usage:

Required flags:

-aHAX
--delete
--numeric-ids
--partial

Incremental snapshots must use:

--link-dest

Snapshots must never overwrite previous snapshots.

Directory naming:

Daily snapshots:

YYYY-MM-DD

Weekly snapshots:

YYYY-WW

Monthly snapshots:

YYYY-MM

Yearly snapshots:

YYYY

Variable naming:

Use uppercase for configuration variables.

Example:

JOB_NAME
DEST_ROOT
BACKUP_PATHS

Functions must use lowercase.

Example:

log()
rotate_snapshots()
create_snapshot()

Paths must always be quoted:

"$DEST_ROOT"

Never rely on implicit word splitting.