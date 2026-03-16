#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/backup-system"
SYSTEMD_DIR="/etc/systemd/system"

echo "=== Backup System Uninstaller ==="

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

# Parse arguments
REMOVE_BACKUPS=false
KEEP_BACKUPS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --remove-backups)
      REMOVE_BACKUPS=true
      shift
      ;;
    --keep-backups)
      KEEP_BACKUPS=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--keep-backups|--remove-backups]"
      exit 1
      ;;
  esac
done

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

if [[ "$REMOVE_BACKUPS" == "true" ]]; then
  echo "Removing backup repository..."
  rm -rf /backup-repo
  echo "Backups removed."
elif [[ "$KEEP_BACKUPS" == "true" ]]; then
  echo "Keeping backup repository at /backup-repo"
else
  echo ""
  echo "WARNING: Backup repository remains at /backup-repo"
  echo "To remove it, run: sudo rm -rf /backup-repo"
  echo "Or uninstall with: sudo $0 --remove-backups"
fi

echo ""
echo "Uninstallation complete."
