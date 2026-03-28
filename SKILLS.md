# SKILLS.md

Agent skill catalog for the backup-system repository. Every automated or semi-automated action **must** be expressed as one of the skills below. Skills only wrap the production-hardened scripts that already live in `bin/` and the systemd units in `systemd/`. No ad-hoc commands are allowed outside these skills (see AGENTS.md for enforcement rules).

---

## Skill Directory

| Skill ID          | Entry Point                           | Purpose                                                   |
|-------------------|---------------------------------------|-----------------------------------------------------------|
| `backup.run`      | `bin/backup-job.sh`                   | Execute a full incremental backup cycle for a job.        |
| `backup.run.dry`  | `bin/backup-job.sh --dry-run`         | Validate a job end-to-end without modifying snapshots.    |
| `backup.seed`     | `bin/seed-backup.sh`                  | Create or resume the very first full snapshot for a job.  |
| `job.create`      | `bin/create-job.sh`                   | Scaffold a new job configuration and its systemd timer.   |
| `schedule.reload` | `systemd/backup-job@.service/.timer`  | Reload + inspect systemd units that execute the jobs.     |
| `state.inspect`   | `/var/lib/backup-state/<job>/` files  | Read structured state emitted by `lib/backup-lib.sh`.     |

Each skill is detailed below with inputs, outputs, safety constraints, and direct mapping to repository artifacts.

---

## Skill: `backup.run`

- **Description**: Runs the main snapshot workflow (daily + promotions + retention) for a given job. Uses flock locking, structured logging, and state updates defined in `lib/backup-lib.sh`.
- **Command**

```bash
bin/backup-job.sh [--dry-run] <job_name | config/jobs/<job>.env>
```

- **Inputs**
  - `job_ref` (required): Either the bare job name (to resolve `config/jobs/<job>.env`) or an explicit `.env` path.
  - `mode` (optional): `--dry-run` flag triggers validation-only behavior; omit for production runs.
- **Outputs**
  - Snapshot directories under `/backup-repo/snapshots/<job>/`.
  - Log file: `/var/log/backup-system/<job>/<YYYY-MM-DD>.log`.
  - State files written through `write_state()` into `/var/lib/backup-state/<job>/`.
- **Rules**
  1. Never pass raw source paths; rely on the job's `BACKUP_PATHS`.
  2. Run only when the job's destination filesystem is mounted (if `REQUIRE_MOUNT=1`).
  3. Abort if a daily snapshot with the same date already exists.
- **Mapping**
  - Script: `bin/backup-job.sh`
  - Library dependencies: `lib/backup-lib.sh`
  - System layout: `/backup-repo/snapshots`, `/var/log/backup-system`, `/var/lib/backup-state`

---

## Skill: `backup.run.dry`

- **Description**: Same execution path as `backup.run`, but always passes `--dry-run` to produce logs/state without touching snapshots. Required before altering job configs.
- **Command**

```bash
bin/backup-job.sh --dry-run <job_name | config/jobs/<job>.env>
```

- **Inputs**
  - `job_ref` (required): Same resolution rules as `backup.run`.
- **Outputs**
  - Log + state entries tagged as `DRY_RUN`. No mutations under `/backup-repo`.
- **Rules**
  1. Use before any new job hits production or after config changes.
  2. Do not skip even if SOURCE_HOST is localhost; integrity checks still apply.
- **Mapping**
  - Script: `bin/backup-job.sh`
  - State contract: `lib/backup-lib.sh::write_state`

---

## Skill: `backup.seed`

- **Description**: Performs or resumes the initial full backup for a job, writing a `.seeding` snapshot until completion.
- **Command**

```bash
bin/seed-backup.sh <job_name | config/jobs/<job>.env>
```

- **Inputs**
  - `job_ref` (required): Same pattern as `backup.run`.
- **Outputs**
  - Temporary seeding snapshot: `/backup-repo/snapshots/<job>/daily/<date>.seeding`
  - Final snapshot: `/backup-repo/snapshots/<job>/daily/<date>`
  - State keys: `seed_snapshot`, `seed_last_path`, `last_status`
- **Rules**
  1. Use exactly once per job unless a previous seed was interrupted.
  2. Killing the process leaves `.seeding` data that must only be resumed via this skill.
  3. Do not run in parallel with `backup.run`.
- **Mapping**
  - Script: `bin/seed-backup.sh`
  - Shared library: `lib/backup-lib.sh`

---

## Skill: `job.create`

- **Description**: Generates a new job configuration, timer, and enables the timer under systemd using production-safe defaults.
- **Command**

```bash
sudo bin/create-job.sh <job_name> <HH:MM>
```

- **Inputs**
  - `job_name` (required): Lowercase + dashes recommended; becomes part of unit names.
  - `schedule` (required): 24h time string validated by the script.
- **Outputs**
  - Config file: `/opt/backup-system/config/jobs/<job>.env`
  - Timer: `/etc/systemd/system/backup-<job>.timer`
  - Enabled systemd timer instance.
- **Rules**
  1. Run with privileges that can write under `/etc/systemd/system`.
  2. After execution, run `backup.run.dry` on the new job before permitting timers to continue unattended.
  3. Never edit timers manually; re-run this skill if changes are needed.
- **Mapping**
  - Script: `bin/create-job.sh`
  - Systemd definitions: `systemd/backup-job@.service`, `systemd/backup-job@.timer`

---

## Skill: `schedule.reload`

- **Description**: Reloads systemd units after template changes and inspects their status to confirm agent-driven deployments.
- **Command**

```bash
sudo systemctl daemon-reload
sudo systemctl status backup-job@<job>.service --no-pager
sudo systemctl list-timers "backup-*.timer"
```

- **Inputs**
  - `job_name` (optional): When provided, scope the status command to the instance.
- **Outputs**
  - systemd status output used for agent decision-making/logging.
- **Rules**
  1. Use immediately after modifying files under `systemd/`.
  2. Read-only skill except for the daemon-reload; does **not** start jobs.
  3. Never call `systemctl start/stop rsync` directly; job execution remains in `backup.run`.
- **Mapping**
  - Files: `systemd/backup-job@.service`, `systemd/backup-job@.timer`
  - Service names: `backup-job@<job>.service`, `backup-<job>.timer`

---

## Skill: `state.inspect`

- **Description**: Reads the canonical state files produced by the scripts to give agents observable signals without parsing logs.
- **Command**

```bash
STATE_DIR=/var/lib/backup-state/<job>
cat "$STATE_DIR/last_status"
cat "$STATE_DIR/last_run"
cat "$STATE_DIR/last_snapshot"
```

- **Inputs**
  - `job_name` (required): Matches the `JOB_NAME` in the config.
  - `state_keys` (optional): restrict reads to the required keys.
- **Outputs**
  - Plain-text key/value data exactly as flushed by `write_state`.
- **Rules**
  1. Read-only: never modify or delete files under `/var/lib/backup-state`.
  2. Treat missing files as a signal that the related skill never ran successfully.
  3. When discrepancies appear, trigger `backup.run.dry` to revalidate.
- **Mapping**
  - Library: `lib/backup-lib.sh::write_state`
  - Directory contract: `/var/lib/backup-state/<job>/`

---

## Global Skill Usage Rules

1. Always resolve skill selection before touching the shell. If a task is not expressible via the listed skills, stop and extend this catalog first.
2. Never invoke `rsync`, `systemctl`, or `rm -rf` outside the scripts/commands referenced above.
3. Capture stdout/stderr from each skill run and attach it to automation logs so operators can audit outcomes.
4. Skills may be composed (e.g., `job.create` → `backup.run.dry` → `schedule.reload`) but must run sequentially to preserve locking guarantees.
5. All skills inherit the safety flags already enforced inside the scripts: `set -Eeuo pipefail`, flock locking, and structured logging.
