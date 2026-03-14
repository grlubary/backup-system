# BACKUP_RULES.md

Backup architecture rules.

Snapshot policy:

GFS retention model:

daily
weekly
monthly
yearly

Default retention:

daily:   7
weekly:  4
monthly: 12
yearly:  5

Snapshots are implemented using rsync hardlinks.

Required rsync flags:

-aHAX
--delete
--numeric-ids

Snapshots must use:

--link-dest

Snapshots must remain browseable via filesystem.

No proprietary formats allowed.

Backup sources must support multiple paths:

BACKUP_PATHS=(
/etc
/home
/var/www
)

All jobs are defined in:

config/jobs/