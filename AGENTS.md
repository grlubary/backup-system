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