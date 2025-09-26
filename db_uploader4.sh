#!/bin/bash
#
# FTP DB uploader (uploads 5 files daily in rotation from yesterday's backups in /FRCFR/backup/db_backup)
#

SRC_DIR="/FRCFR/backup/db_backup"
STATE_FILE="/var/log/db_upload.state"
LOG_FILE="/var/log/db_upload.log"

FTP_SERVER="172.16.16.59"
FTP_USER="kanchidb"
FTP_PASS="kanchidb@9*"

# Collect only yesterday's files
YESTERDAY_ALLFILES=$(find "$SRC_DIR" -maxdepth 1 -type f -daystart -mtime 1 | sort)

# Convert into array
FILES_ARRAY=()
for f in $YESTERDAY_ALLFILES; do
    FILES_ARRAY[${#FILES_ARRAY[@]}]="$f"
done
TOTAL=${#FILES_ARRAY[@]}

if [ $TOTAL -eq 0 ]; then
    echo "[$(date)] No files found for yesterday in $SRC_DIR" >> "$LOG_FILE"
    exit 0
fi

# If state file does not exist, start from 0
if [ ! -f "$STATE_FILE" ]; then
    echo 0 > "$STATE_FILE"
fi

START_INDEX=$(cat "$STATE_FILE")
END_INDEX=$((START_INDEX + 5))

# If END_INDEX exceeds total, cap it
if [ $END_INDEX -gt $TOTAL ]; then
    END_INDEX=$TOTAL
fi

# Files to upload today
TODAY_FILES=("${FILES_ARRAY[@]:$START_INDEX:$((END_INDEX-START_INDEX))}")

echo "[$(date)] Uploading yesterday's files: ${TODAY_FILES[*]}" >> "$LOG_FILE"

for file in "${TODAY_FILES[@]}"; do
    if [ -f "$file" ]; then
        BASENAME=$(basename "$file")
        ftp -inv "$FTP_SERVER" >> "$LOG_FILE" 2>&1 <<EOF
user $FTP_USER $FTP_PASS
put "$file" "$BASENAME"
bye
EOF
        echo "[$(date)] Uploaded: $file" >> "$LOG_FILE"
    else
        echo "[$(date)] Skipped (not found): $file" >> "$LOG_FILE"
    fi
done

# Update state file (rotation)
NEW_INDEX=$END_INDEX
if [ $NEW_INDEX -ge $TOTAL ]; then
    NEW_INDEX=0
fi
echo $NEW_INDEX > "$STATE_FILE"

# Update state for next run
#echo $END_INDEX > "$STATE_FILE"
