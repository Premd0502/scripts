#!/bin/bash
ftp_host="172.16.18.135"
ftp_user="ftpuser"
ftp_pass="ftpuser"
ftp_dir="/uploads"
local_tmp="/var/ftp/uploads"

mkdir -p "$local_tmp"
lftp -u "$ftp_user","$ftp_pass" "$ftp_host" <<EOF
mirror --only-newer --parallel=1 --verbose $ftp_dir $local_tmp
bye
EOF

# Then parse new files and insert into MySQL
for f in $local_tmp/*; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    fsize=$(stat -c%s "$f")
    mysql -uroot -pIql720avyogtWHZf pdfdb <<SQL
INSERT IGNORE INTO file_metadata (filename, filesize, received_time, processed_status)
VALUES ('$fname', $fsize, NOW(), 'pending');
echo "Inserted: $fname ($fsize bytes)"
ON DUPLICATE KEY UPDATE
    processed_status = IF(assigned_node IS NULL, 'pending', processed_status),
    received_time = NOW();
SQL
done

