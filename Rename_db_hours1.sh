#!/bin/bash
# Description: Rename today's backup files by removing hour tags like _00h or _09h

backup_date=$(date -I)
backup_dir="/itshare/Telecom-DB-Backup/aclsys/chennai_db"

# Verify backup directory exists
if [ ! -d "$backup_dir" ]; then
    echo "Error: Backup directory not found: $backup_dir"
    exit 1
fi

cd "$backup_dir" || exit 1

# Rename all matching backup files (e.g., *_2025-10-07_00h.sql.zip → *_2025-10-07.sql.zip)
for file in *"${backup_date}"_*h.sql.zip; do
    # Check if file exists to avoid error when pattern doesn't match
    [ -e "$file" ] || continue

    # Remove _??h part using sed
    new_name=$(echo "$file" | sed -E "s/_[0-9]{2}h//")
    
    # Rename only if new name differs
    if [ "$file" != "$new_name" ]; then
        mv -v "$file" "$new_name"
    fi
done

echo "✅ Backup file rename completed for date: $backup_date"
