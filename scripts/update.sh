#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/backup-system"

echo "Updating backup-system..."

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  echo "Missing git repository in $INSTALL_DIR"
  exit 1
fi

cd "$INSTALL_DIR"

git pull --ff-only

echo "Reloading systemd..."

systemctl daemon-reload

echo "Update complete."
