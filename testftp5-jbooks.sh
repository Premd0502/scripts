#!/bin/sh
# ==========================================================
# Script Name : testftp4.jbooks.sh
# Purpose     : Fetch yesterday's JSTOR ZIP files via SFTP
#               and move them into customer input folder
# ==========================================================

# ---------- CONFIG ----------
export SSHPASS="25varro4"

WORK_DIR="/opt/jbooks"
LOCAL_DOWNLOAD_DIR="/data/ftp"
DEST_DIR="/data/icp_jbooks/files/customerinput"

SFTP_USER="rfpv1"
SFTP_HOST="ftp.jstor.org"
SFTP_PORT="2222"
REMOTE_DIR="/To-Ninestars/books"

# ---------- PREP ----------
cd "$WORK_DIR" || exit 1
mkdir -p "$LOCAL_DOWNLOAD_DIR"
mkdir -p "$DEST_DIR"

echo "======================================"
echo "JBOOKS FTP JOB STARTED : $(date)"
echo "======================================"

# ---------- GET FILE LIST ----------
/bin/sh /opt/jbooks/sshpass-sftp.sh > ftpList1.txt

if [ ! -s ftpList1.txt ]; then
    echo "[ERROR] FTP listing failed or empty."
    exit 1
fi

# Filter current month
grep "$(date +"%b")" ftpList1.txt > ftpList2.txt

# Filter yesterday (e.g. Jan 18)
grep "$(date --date='yesterday' +"%b %d")" ftpList2.txt > ftpList.txt
#grep "$(date --date='2 days ago' +"%b %d")" ftpList2.txt > ftpList.txt

# ---------- EXTRACT FILENAMES ----------
files=$(awk '{print $9}' ftpList.txt)

echo "Files to download:"
echo "$files"

if [ -z "$files" ]; then
    echo "[INFO] No files found for yesterday."
    exit 0
fi

# ---------- DOWNLOAD FILES ----------
(
  echo "cd $REMOTE_DIR"
  echo "lcd $LOCAL_DOWNLOAD_DIR"
  for file in $files; do
    echo "get $file"
  done
) | sshpass -e sftp \
    -oPort=$SFTP_PORT \
    -oStrictHostKeyChecking=no \
    -oUserKnownHostsFile=/dev/null \
    -oBatchMode=no \
    -b - "$SFTP_USER@$SFTP_HOST"

SFTP_RC=$?

if [ $SFTP_RC -ne 0 ]; then
    echo "[ERROR] SFTP download failed (rc=$SFTP_RC)."
    exit 1
fi

# ---------- VERIFY DOWNLOAD ----------
ZIP_COUNT=$(ls "$LOCAL_DOWNLOAD_DIR"/*.zip 2>/dev/null | wc -l)

if [ "$ZIP_COUNT" -eq 0 ]; then
    echo "[ERROR] No ZIP files downloaded. SFTP likely failed."
    exit 1
fi

# ---------- MOVE ZIP FILES ----------
echo "[INFO] Moving ZIP files to $DEST_DIR"

/bin/mv "$LOCAL_DOWNLOAD_DIR"/*.zip "$DEST_DIR"/

MV_RC=$?

if [ $MV_RC -ne 0 ]; then
    echo "[ERROR] ZIP file move failed (rc=$MV_RC)."
    exit 1
fi

echo "======================================"
echo "JBOOKS FTP JOB COMPLETED : $(date)"
echo "======================================"

chown -R jbookscustin:jbookscustin /data/icp_jbooks/files/customerinput/*.zip
