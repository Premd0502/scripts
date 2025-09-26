#!/bin/bash

# Define backup name for yesterday
backup_date=$(date -I)
backup_dir="/NLN1-data/DBBACKUP_RDL"
backup_sql="coc_rdl_${backup_date}.sql"
backup_zip="coc_rdl_${backup_date}.sql.zip"

# Step 1: Dump SQL into currentday's file
mysqldump --routines -uroot -p'MyD6Km$@9*' coc_rdl > "${backup_dir}/${backup_sql}"

# Step 2: Zip only the file (without directory structure)
(
  cd "$backup_dir" || exit 1
  zip --password B@CkU9i9d "$backup_zip" "$backup_sql"
)

# Step 3: Remove plain SQL file for security
rm -f "${backup_dir}/${backup_sql}"
