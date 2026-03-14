# MONITOR_RULES.md

Monitoring integration rules.

Backup scripts must produce state files in:

/var/lib/backup-state/<job>/

Required files:

last_run
last_success
last_duration
last_snapshot
last_status
last_size

Exit codes:

0 = OK
1 = WARNING
2 = CRITICAL

Monitoring agents read these files to determine backup status.

The monitoring system does NOT execute backups.

Backups run locally via systemd timers.