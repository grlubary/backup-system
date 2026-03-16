#!/usr/bin/env bash
set -Eeuo pipefail

REPO_BASE="https://raw.githubusercontent.com/grlubary/backup-system/main"
INSTALL_DIR="/opt/backup-system"
SYSTEMD_DIR="/etc/systemd/system"

echo "=== Backup System Installer ==="

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Installing dependencies..."

apt-get update
apt-get install -y rsync curl util-linux

echo "Creating installation directory..."

if [[ -d "$INSTALL_DIR" ]]; then
  echo "Directory already exists: $INSTALL_DIR"
  echo "Removing existing installation..."
  rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR"

echo "Downloading backup system files..."

# Create directory structure
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/config/jobs"
mkdir -p "$INSTALL_DIR/config/excludes"
mkdir -p "$INSTALL_DIR/systemd"
mkdir -p "$INSTALL_DIR/docs"

# Download core scripts
curl -s -o "$INSTALL_DIR/bin/backup-job.sh" "$REPO_BASE/bin/backup-job.sh"
curl -s -o "$INSTALL_DIR/lib/backup-lib.sh" "$REPO_BASE/lib/backup-lib.sh"

# Download configuration files
curl -s -o "$INSTALL_DIR/config/jobs/example-job.env" "$REPO_BASE/config/jobs/example-job.env"
curl -s -o "$INSTALL_DIR/config/jobs/webserver.env" "$REPO_BASE/config/jobs/webserver.env"
curl -s -o "$INSTALL_DIR/config/excludes/linux-common.txt" "$REPO_BASE/config/excludes/linux-common.txt"

# Download systemd files
curl -s -o "$INSTALL_DIR/systemd/backup-job@.service" "$REPO_BASE/systemd/backup-job@.service"
curl -s -o "$INSTALL_DIR/systemd/backup-job@.timer" "$REPO_BASE/systemd/backup-job@.timer"

# Make scripts executable
chmod +x "$INSTALL_DIR/bin/backup-job.sh"

echo "Creating directories..."

mkdir -p /var/log/backup-system
mkdir -p /var/lib/backup-state

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
