# AGENTS.md

Guidelines for AI agents working on the backup-system repository.

Purpose:
Maintain a simple, robust, production-grade backup system.

Core technologies:

- Bash
- rsync
- hardlink snapshots
- GFS retention
- systemd timers

Repository structure:

bin/
    backup-job.sh

lib/
    reusable bash functions

config/jobs/
    job configuration files

config/excludes/
    rsync exclude lists

docs/
    architecture documentation

systemd/
    service and timer definitions

Rules:

1. Never remove safety flags from bash scripts.

Required:

set -Eeuo pipefail

2. All backup scripts must support:

- flock locking
- structured logging
- error handling

3. Snapshots must always use:

rsync --link-dest

4. Snapshot layout must remain:

/backup-repo/snapshots/<job>/

    daily
    weekly
    monthly
    yearly

5. Do not introduce databases or complex dependencies.

The system must remain simple and portable.

6. Monitoring must rely on state files.

State directory:

/var/lib/backup-state/<job>/

## Execution Rules

- Skills-first: before running any command, select the appropriate entry from `SKILLS.md`. If no skill covers the action, stop and extend the skill catalog instead of improvising.
- Command boundaries: the only executable entry points are the scripts referenced in `SKILLS.md` (`bin/backup-job.sh`, `bin/seed-backup.sh`, `bin/create-job.sh`) plus the systemd units shipped under `systemd/`. Ad-hoc `rsync`, `rm -rf`, `systemctl start/stop`, or direct snapshot manipulation are forbidden.
- Locking & safety: never bypass flock locks, logging, or error handlers already implemented inside the scripts. Running the same underlying tool outside the skill layer is considered a violation.
- Verification: every change to job configuration or systemd units must execute `backup.run.dry` (see `SKILLS.md`) before enabling or restarting timers.
- Observability: agents must read `/var/lib/backup-state/<job>/` via the `state.inspect` skill instead of tailing logs directly, ensuring consistent state consumption.
