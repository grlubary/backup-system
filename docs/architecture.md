# Backup System Architecture

The backup system follows a distributed execution model.

Each server runs backup jobs locally or from a central backup node.

Backup jobs create snapshots using rsync and hardlinks.

Storage layout:

/backup-repo
    /snapshots
        /<job>
            /daily
            /weekly
            /monthly
            /yearly

Retention uses a GFS model.

Snapshots remain browseable from the filesystem.

Monitoring is implemented through state files.

Future components:

- central monitoring server
- Grafana dashboards
- alerting via email or WhatsApp