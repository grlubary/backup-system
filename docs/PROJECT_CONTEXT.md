# PROJECT_CONTEXT.md

Project: backup-system

Goal:
Build a simple, robust and production-grade backup system for Linux infrastructure.

Primary technologies:

- Bash
- rsync
- filesystem snapshots using hardlinks
- GFS retention policy
- systemd timers

The system must remain:

- simple
- portable
- easy to operate
- easy to monitor
- safe against data loss

Snapshots must always remain browsable directly from the filesystem.

No proprietary backup formats are allowed.

Example snapshot layout:

/backup-repo/snapshots/<job>/

    daily/
    weekly/
    monthly/
    yearly/

Each backup job is defined by a configuration file:

config/jobs/<job>.env

Example:

JOB_NAME="webserver"

SOURCE_HOST="root@10.0.0.5"

BACKUP_PATHS=(
/etc
/home
/var/www
)

DEST_ROOT="/backup-repo"

Retention policy uses GFS:

daily
weekly
monthly
yearly

Monitoring integration relies on state files written to:

/var/lib/backup-state/<job>/

The monitoring system reads these files but never runs backups itself.
