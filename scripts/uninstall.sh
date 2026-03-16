#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/backup-system"
SYSTEMD_DIR="/etc/systemd/system"

echo "=== Backup System Uninstaller ==="

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Disabling backup timers and services..."

# Disable and stop all backup timers
systemctl disable backup-job@*.timer 2>/dev/null || true
systemctl stop backup-job@*.timer 2>/dev/null || true
systemctl disable backup-job@*.service 2>/dev/null || true
systemctl stop backup-job@*.service 2>/dev/null || true

echo "Removing systemd service and timer definitions..."

rm -f "$SYSTEMD_DIR/backup-job@.service"
rm -f "$SYSTEMD_DIR/backup-job@.timer"

systemctl daemon-reload

echo "Removing installation directory..."

rm -rf "$INSTALL_DIR"

echo "Cleaning up state and log directories..."

rm -rf /var/lib/backup-state
rm -rf /var/log/backup-system

echo ""
echo "Uninstallation complete."
