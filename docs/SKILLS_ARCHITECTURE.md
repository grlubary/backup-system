# SKILLS_ARCHITECTURE.md

## Overview

The backup-system repository now exposes an explicit skill layer so that automation agents, operators, and CI pipelines can trigger production-safe actions without learning every bash detail. Three documents work together:

1. `AGENTS.md` – defines guardrails and mandates skill usage (`Execution Rules` section).
2. `SKILLS.md` – authoritative catalog of skills, inputs/outputs, and the scripts or units they wrap.
3. This document – explains how the Markdown control plane maps to executable artifacts under `bin/`, `lib/`, and `systemd/`.

The guiding principle remains unchanged: prefer simple bash scripts with strict safety flags, and let the skill layer describe **when** and **how** those scripts run.

## Components

| Layer              | Location                               | Purpose                                                                          |
|--------------------|----------------------------------------|----------------------------------------------------------------------------------|
| Skills contract    | `SKILLS.md`                            | Lists every allowed action and the exact command syntax to invoke it.           |
| Agent policies     | `AGENTS.md`                            | Forces agents to choose a skill, bans direct dangerous commands.                |
| Executable scripts | `bin/backup-job.sh`, `bin/seed-backup.sh`, `bin/create-job.sh` | Implement locking, logging, rsync orchestration, and job scaffolding. |
| Shared library     | `lib/backup-lib.sh`                    | Provides reusable functions (`write_state`, locking, snapshot helpers).         |
| System scheduling  | `systemd/backup-job@.service` + `.timer` | Runs `bin/backup-job.sh` per job via timers.                                   |
| State + logs       | `/var/lib/backup-state/<job>/`, `/var/log/backup-system/<job>/` | Persistent telemetry read by the `state.inspect` skill.                    |

## Execution Flow

1. **Agent selects a skill** – e.g., `backup.run`.
2. **Agent invokes the mapped script** – run `bin/backup-job.sh <job>` from the repository (or `/opt/backup-system` in production). The script sources `lib/backup-lib.sh`.
3. **Script performs work** – acquires flock, runs rsync with `--link-dest`, validates snapshots, and writes logs/state.
4. **State exposed to agents** – `write_state` flushes outcome files under `/var/lib/backup-state/<job>/`.
5. **Agents observe via `state.inspect`** – read-only operations fetch `last_status`, `last_run`, etc., without parsing raw logs.
6. **Systemd orchestration** – timers defined in `systemd/backup-job@.timer` trigger `backup-job@.service`, which executes `bin/backup-job.sh`. After editing any timer/service file, the `schedule.reload` skill (`systemctl daemon-reload` + status checks) is mandatory.

The flow ensures every automated action can be audited back to a concrete skill invocation, which in turn corresponds to a vetted script.

## Adding a New Skill

To extend the catalog without breaking production safety:

1. **Identify or write the script** under `bin/` (or add a new helper under `scripts/` if the action is read-only). Apply the standard bash requirements (`set -Eeuo pipefail`, locking, structured logging).
2. **Update `SKILLS.md`**: add the new skill to the directory table, describe inputs/outputs, and reference the script path explicitly.
3. **Amend `AGENTS.md` Execution Rules`** only if the new skill changes global policies (rare). Otherwise the existing rules already enforce skill usage.
4. **Document wiring here**: describe how the skill interacts with existing components (library functions, state directories, timers).
5. **Validate with `backup.run.dry`** or the appropriate dry skill if the new action mutates data.

## Interaction Examples

- **Onboarding a new job**  
  1. Run `job.create` to scaffold config + timer.  
  2. Execute `backup.seed` to build the first snapshot.  
  3. Execute `backup.run.dry` to validate day-to-day workflow.  
  4. Confirm timers via `schedule.reload`.  
  5. Monitor readiness via `state.inspect`.

- **Investigating a failure**  
  1. Use `state.inspect` to read `last_status`.  
  2. Trigger `backup.run.dry` for diagnostics (shares log files).  
  3. If config edits were required, re-run `backup.run` only after a green dry run.

## Design Constraints

- No new dependencies: skills are documentation + enforced workflows, not extra binaries.
- Skills remain composable; agents can chain them but never parallelize the same job (locking).
- The library (`lib/backup-lib.sh`) is the single source of truth for state format. Any script that wants to become a skill must adopt its helpers.

By keeping the Markdown control plane tightly coupled with the existing bash scripts, we achieve an “agent-ready” architecture without touching the proven production logic.
