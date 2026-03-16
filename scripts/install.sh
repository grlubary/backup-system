#!/usr/bin/env bash
set -Eeuo pipefail

REPO="https://github.com/grlubary/backup-system.git"
INSTALL_DIR="/opt/backup-system"
SYSTEMD_DIR="/etc/systemd/system"

echo "=== Backup System Installer ==="

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Installing dependencies..."

apt-get update
apt-get install -y rsync git util-linux

echo "Cloning repository..."

if [[ -d "$INSTALL_DIR" ]]; then
  echo "Directory already exists: $INSTALL_DIR"
else
  git clone "$REPO" "$INSTALL_DIR"
fi

echo "Creating directories..."

mkdir -p /var/log/backup-system
mkdir -p /var/lib/backup-state
mkdir -p "$INSTALL_DIR/config/jobs"

echo "Installing systemd service..."

install -m 0644 "$INSTALL_DIR/systemd/backup-job@.service" "$SYSTEMD_DIR/backup-job@.service"
install -m 0644 "$INSTALL_DIR/systemd/backup-job@.timer" "$SYSTEMD_DIR/backup-job@.timer"

systemctl daemon-reload

echo "Installation complete."

echo
echo "Next steps:"
echo "1. copy $INSTALL_DIR/config/jobs/example-job.env to your job file"
echo "2. edit source, paths and retention values"
echo "3. test with: $INSTALL_DIR/bin/backup-job.sh --dry-run <job>"
echo "4. enable timer: systemctl enable --now backup-job@<job>.timer"
