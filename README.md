# Backup System

Sistema de backups basado en:

- rsync
- snapshots con hardlinks
- política GFS

Características:

- daily / weekly / monthly / yearly
- múltiples directorios por servidor
- restauración simple
- integración con monitoreo
- dry-run para validación inicial
- preflight checks de destino y dependencias

Repositorio principal de snapshots:

/backup-repo/snapshots

Primera prueba recomendada:

1. Copiar `config/jobs/example-job.env` a un archivo real de job.
2. Ajustar `SOURCE_HOST`, `BACKUP_PATHS` y `DEST_ROOT`.
3. Ejecutar `bin/backup-job.sh --dry-run <job>`.
4. Si el dry-run es correcto, habilitar `systemctl enable --now backup-job@<job>.timer`.

# Crear job configurción:

cp config/jobs/example-job.env config/jobs/myjob.env

Enable the timer:

sudo systemctl enable backup-job@myjob.timer
sudo systemctl start backup-job@myjob.timer

sudo systemctl daemon-reload

# Run a backup manualmente

/opt/backup-system/bin/backup-job.sh myjob

# Uninstall
# Disable timers:

sudo systemctl disable backup-job@*.timer
sudo systemctl stop backup-job@*.timer

sudo rm /etc/systemd/system/backup-job@.service
sudo rm /etc/systemd/system/backup-job@.timer
sudo systemctl daemon-reload

sudo rm -rf /opt/backup-system