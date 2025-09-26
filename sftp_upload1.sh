#!/bin/bash

# Variables
LOCAL_DIR="/itshare/Telecom-DB-Backup/aclsys/chennai_db/"   # Local directory containing the files to be uploaded
REMOTE_DIR="dbbackup" # Remote directory on the SFTP server
SFTP_USER="sftpuser"                   # SFTP Username
SFTP_HOST="192.168.5.197"              # SFTP Server IP or hostname
SFTP_PORT="41999"                      # SFTP Port
SFTP_PASSWORD="sftpuser@9*"            # SFTP Password (handle this carefully)
LOG_FILE="/itshare/Telecom-DB-Backup/aclsys/sftp_upload.log"    # Log file path

# Function to upload yesterday's files
upload_yesterday_files() {
    # Find all files in LOCAL_DIR modified 1 day ago (-mtime 1)
    find "$LOCAL_DIR" -type f -mtime 1 | while read -r file; do
        echo "Uploading: $(basename "$file")"

        # Use sshpass to pass the password and upload files via SFTP
        sshpass -p "$SFTP_PASSWORD" sftp -P "$SFTP_PORT" "$SFTP_USER@$SFTP_HOST" <<EOF
cd "$REMOTE_DIR"
put "$file"
EOF

        # Check if the upload was successful
        if [ $? -eq 0 ]; then
            echo "$(date): Successfully uploaded $(basename "$file")" >> "$LOG_FILE"
        else
            echo "$(date): Failed to upload $(basename "$file")" >> "$LOG_FILE"
        fi
    done
}

# Call the function to start the upload process
upload_yesterday_files
