#!/usr/bin/env bash

# Crea un nuevo job de backup con un timer systemd.  
#  /opt/backup-system/bin/create-job.sh ad_homes 03:30
# 

set -Eeuo pipefail
IFS=$'\n\t'
trap 'echo "[ERROR] ${BASH_COMMAND} (line ${LINENO})" >&2' ERR

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <job_name> <HH:MM>"
    exit 1
fi

JOB_NAME="$1"
SCHEDULE="$2"

# Validar formato HH:MM
if ! [[ "$SCHEDULE" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "[ERROR] Invalid schedule format. Use HH:MM (24h)"
    exit 1
fi

BASE_DIR="/opt/backup-system"
JOB_FILE="$BASE_DIR/config/jobs/${JOB_NAME}.env"
TIMER_FILE="/etc/systemd/system/backup-${JOB_NAME}.timer"

echo "[INFO] Creating job: $JOB_NAME"
echo "[INFO] Schedule: $SCHEDULE"

# -------------------------
# 1. Crear .env si no existe
# -------------------------
if [[ -f "$JOB_FILE" ]]; then
    echo "[WARN] Job config already exists: $JOB_FILE"
else
    cat <<EOF > "$JOB_FILE"
JOB_NAME="${JOB_NAME}"

# Leave empty for local backups
SOURCE_HOST=""

BACKUP_PATHS=(
    "/data"
)

DEST_ROOT="/backup/${JOB_NAME}"

DAILY_KEEP=7
WEEKLY_KEEP=4
MONTHLY_KEEP=12

RSYNC_SSH="ssh -o BatchMode=yes"

EXCLUDE_FILE="${BASE_DIR}/config/excludes/linux-common.txt"

LOG_ROOT="/var/log/backup-system"
STATE_ROOT="/var/lib/backup-state"

# Seguridad de mount (RECOMENDADO en producción)
REQUIRE_MOUNT=1
MOUNT_POINT="/backup"

MIN_SNAPSHOT_SIZE_BYTES=1
MIN_EXPECTED_ENTRIES=1
EOF

    echo "[OK] Created job config"
fi

# -------------------------
# 2. Crear timer limpio
# -------------------------
cat <<EOF > "$TIMER_FILE"
[Unit]
Description=Schedule backup job ${JOB_NAME}

[Timer]
OnCalendar=*-*-* ${SCHEDULE}:00
Persistent=true
RandomizedDelaySec=10m
Unit=backup-job@${JOB_NAME}.service

[Install]
WantedBy=timers.target
EOF

echo "[OK] Timer created: $TIMER_FILE"

# -------------------------
# 3. Permisos correctos
# -------------------------
chmod 644 "$TIMER_FILE"

# -------------------------
# 4. Reload limpio
# -------------------------
systemctl daemon-reexec
systemctl daemon-reload

# -------------------------
# 5. Activar timer
# -------------------------
systemctl enable --now "backup-${JOB_NAME}.timer"

echo "[OK] Timer enabled and started"

# -------------------------
# 6. Status
# -------------------------
systemctl status "backup-${JOB_NAME}.timer" --no-page