#!/bin/bash
BACKUP_DIR="/root/sportdata/backups"
FILENAME="db_$(date +%Y%m%d_%H%M%S).sql.gz"

mkdir -p $BACKUP_DIR

docker exec sportdata-postgres pg_dump -U sportdata_admin sportdata | gzip > "$BACKUP_DIR/$FILENAME"

SIZE=$(du -h "$BACKUP_DIR/$FILENAME" | cut -f1)
echo "[$(date)] Backup completed: $FILENAME ($SIZE)"

# Удаляем старше 14 дней
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +14 -delete
