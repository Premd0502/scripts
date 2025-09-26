#!/bin/bash

# Backup directory
backup_date=$(date -I)
backup_dir="/NLN1-data/DBBACKUP_RDL"

# MySQL credentials
MYSQL_USER="root"
MYSQL_PASS='MyD6Km$@9*'

# Zip password
ZIP_PASS="B@CkU9i9d"

# List of databases to back up
DB_LIST=("coc_rdl" "coc_rdl_01122024" "coc_rdl_16112023")

# Make sure backup directory exists
mkdir -p "$backup_dir"

for db in "${DB_LIST[@]}"; do
    backup_sql="${db}_${backup_date}.sql"
    backup_zip="${db}_${backup_date}.sql.zip"

    echo "[$(date)] Starting backup for DB: $db"

    # Step 1: Run mysqldump (with password in single quotes for safety)
    mysqldump --routines -u"$MYSQL_USER" -p"$MYSQL_PASS" "$db" > "${backup_dir}/${backup_sql}" 2>>"${backup_dir}/backup_error.log"

    # Alternative safer way (force single quotes):
    # mysqldump --routines -u"$MYSQL_USER" -p'"$MYSQL_PASS"' "$db" > "${backup_dir}/${backup_sql}"

    # Verify dump success
    if [ ! -s "${backup_dir}/${backup_sql}" ]; then
        echo "[$(date)] ❌ Backup failed for $db. Check backup_error.log"
        continue
    fi

    # Step 2: Zip only the file (without directory structure)
    (
      cd "$backup_dir" || exit 1
      zip -j --password "$ZIP_PASS" "$backup_zip" "$backup_sql" >> /dev/null
    )

    # Step 3: Remove plain SQL file
    rm -f "${backup_dir}/${backup_sql}"

    echo "[$(date)] ✅ Backup completed for $db -> $backup_zip"
done

echo "[$(date)] All database backups done. Logs in $backup_dir/backup_error.log"
