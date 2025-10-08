#!/bin/bash
#
# FTP DB uploader (uploads 5 DB backup .zip files daily in rotation)
#

SRC_DIR="/itshare/Telecom-DB-Backup/aclsys/chennai_db"
DBLIST="/opt/premd/dblist_live.txt"
STATE_FILE="/var/log/db_upload.state"
LOG_FILE="/var/log/db_upload.log"

FTP_SERVER="172.16.3.50"
FTP_USER="dbftpuser"
FTP_PASS="dbftpuser@9*"

# Create logs if missing
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE" "$STATE_FILE"

# Read valid DB names (ignore comments and blanks)
mapfile -t DBNAMES < <(grep -v '^\s*$\|^\s*#' "$DBLIST")

TOTAL=${#DBNAMES[@]}
if [ $TOTAL -eq 0 ]; then
    echo "[$(date)] No valid DB entries found in $DBLIST" >> "$LOG_FILE"
    exit 1
fi

# Initialize rotation index
if [ ! -f "$STATE_FILE" ]; then
    echo 0 > "$STATE_FILE"
fi

START_INDEX=$(cat "$STATE_FILE")
END_INDEX=$((START_INDEX + 5))
if [ $END_INDEX -gt $TOTAL ]; then
    END_INDEX=$TOTAL
fi

# Today's date
TODAY_DATE=$(date +%Y-%m-%d)
TODAY_DIR="/upload/backup/${TODAY_DATE}"

echo "[$(date)] Uploading files ${START_INDEX} to $((END_INDEX-1)) out of $TOTAL from $SRC_DIR" >> "$LOG_FILE"

# Upload each DB file
for ((i=START_INDEX; i<END_INDEX; i++)); do
    DBNAME="${DBNAMES[$i]}"
    FILE="${SRC_DIR}/${DBNAME}_${TODAY_DATE}.sql.zip"

    if [ -f "$FILE" ]; then
        BASENAME=$(basename "$FILE")
        ftp -inv "$FTP_SERVER" >> "$LOG_FILE" 2>&1 <<EOF
user $FTP_USER $FTP_PASS
binary
mkdir $TODAY_DIR
cd $TODAY_DIR
put "$FILE" "$BASENAME"
bye
EOF
        echo "[$(date)] Uploaded: $FILE" >> "$LOG_FILE"
    else
        echo "[$(date)] WARNING: File not found - $FILE" >> "$LOG_FILE"
    fi
done

# Update rotation
NEW_INDEX=$END_INDEX
if [ $NEW_INDEX -ge $TOTAL ]; then
    NEW_INDEX=0
fi
echo $NEW_INDEX > "$STATE_FILE"

echo "[$(date)] Rotation complete. Next start index: $NEW_INDEX" >> "$LOG_FILE"
