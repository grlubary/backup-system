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

Estructura de snapshots:

Los snapshots se almacenan en el directorio configurado en `DEST_ROOT` con la estructura:

```
DEST_ROOT/snapshots/<job>/
├── daily/
├── weekly/
├── monthly/
└── yearly/
```

Primera prueba recomendada:

1. Copiar `config/jobs/example-job.env` a un archivo real de job.
2. Ajustar `SOURCE_HOST`, `BACKUP_PATHS` y `DEST_ROOT`.
3. Ejecutar `bin/backup-job.sh --dry-run <job>`.
4. Si el dry-run es correcto, habilitar `systemctl enable --now backup-job@<job>.timer`.

# Install

## Instalación rápida

```bash
curl -s https://raw.githubusercontent.com/grlubary/backup-system/main/scripts/install.sh | sudo bash
```

## Instalación manual

Descargar y ejecutar el script de instalación:

```bash
curl -s https://raw.githubusercontent.com/grlubary/backup-system/main/scripts/install.sh | sudo bash
```

O clonar el repositorio completo para desarrollo:

```bash
git clone https://github.com/grlubary/backup-system.git
cd backup-system
sudo scripts/install.sh
```

Esto instalará:
- Dependencias (rsync, curl, util-linux)
- Sistema de backup en `/opt/backup-system`
- Directorios necesarios (/var/log/backup-system, /var/lib/backup-state)
- Definiciones systemd para servicios y timers

# Configurar un job

Copiar la configuración de ejemplo:

```bash
cp config/jobs/example-job.env config/jobs/myjob.env
```

Editar los parámetros: `SOURCE_HOST`, `BACKUP_PATHS`, `DEST_ROOT` y política de retención.

Probar con dry-run:

```bash
/opt/backup-system/bin/backup-job.sh --dry-run myjob
```

Habilitar el timer (ejecución automática):

```bash
sudo systemctl enable --now backup-job@myjob.timer
```

# Ejecutar backup manualmente

```bash
/opt/backup-system/bin/backup-job.sh myjob
```

# Uninstall

## Desinstalación automática

```bash
sudo scripts/uninstall.sh
```

Esto desinstalará completamente el sistema de backup, incluyendo:
- Deshabilitación y detención de todos los timers y servicios
- Eliminación de las definiciones systemd
- Remoción del directorio de instalación `/opt/backup-system`
- Limpieza de directorios de estado y logs

**Nota**: Los backups existentes en el directorio configurado en `DEST_ROOT` se mantendrán intactos.

## Desinstalación manual

Si prefieres desinstalar paso a paso:

```bash
# Deshabilitar y detener timers
sudo systemctl disable backup-job@*.timer
sudo systemctl stop backup-job@*.timer

# Remover definiciones systemd
sudo rm /etc/systemd/system/backup-job@.service
sudo rm /etc/systemd/system/backup-job@.timer
sudo systemctl daemon-reload

# Remover instalación
sudo rm -rf /opt/backup-system
sudo rm -rf /var/lib/backup-state
sudo rm -rf /var/log/backup-system
```