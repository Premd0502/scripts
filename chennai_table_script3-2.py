#!/usr/bin/env python
# -*- coding: utf-8 -*-
import re
import csv
import datetime
import os
import sys

# If date is passed as argument (YYYY-MM-DD), use it, otherwise use today
if len(sys.argv) > 1:
    date_str = sys.argv[1]
else:
    date_str = datetime.date.today().strftime("%Y-%m-%d")

file_path = "/mnt/hamburg/logs/chennai/chennai_coc_security_audit1_{0}.txt".format(date_str)

try:
    f = open(file_path, "r")
    data = f.read()
    f.close()
except IOError:
    print("File not found: {0}".format(file_path))
    sys.exit(1)
# Split into host blocks
blocks = re.split(r'(\S+\.universe\.com \| SUCCESS \| rc=0 >>)', data)
hosts_data = []
for i in range(1, len(blocks), 2):
    hosts_data.append(blocks[i] + blocks[i+1])

rows = []
for block in hosts_data:
    # Hostname
    m = re.search(r'(\S+\.universe\.com)', block)
    hostname = m.group(1) if m else "Unknown"

    # Extract key: value lines
    info = {}
    for line in block.splitlines():
        kv = re.match(r'([A-Z0-9_/]+):\s*(.*)', line)
        if kv:
            key, value = kv.groups()
            info[key] = value.strip()

    info["HOST"] = hostname
    rows.append(info)

# Define expected columns
columns = [
    "HOST","OS_VERSION","UPTIME","LAST_REBOOT","SELINUX_STATUS",
    "USERS_WITH_UID0","LOCKED_USERS","SSH_ROOT_ALLOWED","SSH_AUTH_METHODS",
    "FAILED_LOGIN_LAST_24H","MALWARE_ROOTKIT_SCAN_RESULT","FILE_INTEGRITY_TOOL_STATUS",
    "MYSQL/DB_REMOTE_BIND","TLS_CERT_EXPIRY","BACKUP_LAST_RUN",
    "TIME_SYNC_STATUS","CRITICAL_LOG_SIZE"
]

# Helper: truncate long values
def shorten(val, length=40):
    if val and len(val) > length:
        return val[:length-3] + "..."
    return val

# Calculate column widths (max of header or values)
col_widths = {}
for col in columns:
    max_len = len(col)
    for row in rows:
        val = shorten(row.get(col, ""))
        if len(val) > max_len:
            max_len = len(val)
    col_widths[col] = max_len + 2  # padding

# Print header
header = " | ".join(col.ljust(col_widths[col]) for col in columns)
print(header)
print("=" * len(header))

# Print rows neatly
for row in rows:
    line = " | ".join(shorten(row.get(c, "")).ljust(col_widths[c]) for c in columns)
    print(line)

# Save CSV (full values, not shortened)
with open("security_audit_report.csv", "w") as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow(columns)
    for row in rows:
        writer.writerow([row.get(c, "") for c in columns])
