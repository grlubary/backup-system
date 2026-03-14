# TASKS.md

Technical roadmap for the backup-system project.

This file lists planned features and implementation steps.

AI agents should follow this roadmap when proposing changes.

---

# Phase 1 — Core Backup Engine

Goal:
Implement a stable rsync snapshot backup system.

Tasks:

- [x] Implement bin/backup-job.sh
- [x] Implement lib/backup-lib.sh
- [x] Implement GFS snapshot policy
- [x] Implement snapshot rotation
- [x] Implement structured logging
- [x] Implement flock locking
- [x] Implement state files for monitoring

---

# Phase 2 — Monitoring Integration

Goal:
Allow monitoring systems to verify backup health.

Tasks:

- [ ] Write state files to /var/lib/backup-state/<job>/
- [ ] Implement last_status
- [ ] Implement last_duration
- [ ] Implement last_snapshot
- [ ] Implement last_size
- [ ] Implement exit codes for monitoring

Future:

- [ ] Integrate with check_backup.sh
- [ ] Integrate with monitor-agent

---

# Phase 3 — Reliability Improvements

Goal:
Improve safety and robustness.

Tasks:

- [x] Detect missing storage mounts
- [x] Detect rsync failures
- [x] Detect empty backups
- [ ] Detect unexpected large deletions
- [x] Add dry-run mode

---

# Phase 4 — Performance Improvements

Goal:
Optimize large infrastructures.

Tasks:

- [ ] Parallel backups
- [ ] Network bandwidth limits
- [ ] IO priority control
- [ ] rsync compression for remote servers

---

# Phase 5 — Notifications

Goal:
Alert administrators about failures.

Tasks:

- [ ] Email alerts
- [ ] Webhook notifications
- [ ] WhatsApp alerts (CallMeBot)
- [ ] Slack integration

---

# Phase 6 — Additional Backup Engines

Goal:
Support additional backup strategies.

Tasks:

- [ ] BorgBackup integration
- [ ] Restic integration
- [ ] Kopia integration
- [ ] rclone cloud backups

---

# Phase 7 — Centralized Dashboard

Future improvements:

- [ ] FastAPI backend
- [ ] Grafana dashboards
- [ ] backup metrics
- [ ] historical statistics
