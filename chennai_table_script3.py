#!/usr/bin/env python3
import re
import datetime
import os
import sys

# If date is passed as argument (YYYY-MM-DD), use it, otherwise use today
if len(sys.argv) > 1:
    date_str = sys.argv[1]
else:
    date_str = datetime.date.today().strftime("%Y-%m-%d")

# Build the file path automatically
input_file = "/mnt/hamburg/logs/chennai/chennai_coc_security_report_{0}.txt".format(date_str)
#input_file = "/mnt/hamburg/logs/chennai/chennai_coc_security_report_2025-09-20.txt"

# Print header
header = [
    "HOST", "USER", "LAST_PASSWORD_CHANGE", "PASSWORD_EXPIRES",
    "PERMIT_ROOT_LOGIN", "SSH_PORT", "ETHERNET_SPEED", "FAILED_LOGINS"
]
print("{0:<35} {1:<10} {2:<20} {3:<20} {4:<20} {5:<12} {6:<15} {7}".format(*header))
print("{0:<35} {1:<10} {2:<20} {3:<20} {4:<20} {5:<12} {6:<15} {7}".format(
    *["-"*len(h) for h in header]
))

# Temporary storage per host
host = user = last_change = expire = permit = port = speed = ""
failed_logins = []
inside_failed_block = False

with open(input_file) as f:
    for line in f:
        line = line.strip()

        # Host marker
        m = re.match(r'(\S+)\s+\|\s+SUCCESS', line)
        if m:
            host = m.group(1)

        # Current user
        m = re.match(r'Current user:\s+(\S+)', line)
        if m:
            user = m.group(1)

        # Last password change
        m = re.search(r'Last password change\s*:\s*(\w+ \d{1,2}, \d{4})', line)
        if m:
            last_change = m.group(1)

        # Password expires
        m = re.search(r'Password expires\s*:\s*(\w+ \d{1,2}, \d{4})', line)
        if m:
            expire = m.group(1)

        # PermitRootLogin
        m = re.match(r'PermitRootLogin\s*:? *(.*)', line)
        if m:
            permit = m.group(1) if m.group(1) else "Not set"

        # SSH Port
        m = re.match(r'SSH Port\s*:? *(.*)', line)
        if m:
            port = m.group(1)

        # Ethernet Speed
        m = re.match(r'Ethernet Speed:\s*(.*)', line)
        if m:
            speed = m.group(1)

        # Start failed login block
#        if "Failed login attempts" in line:
#            failed_logins = []
#            inside_failed_block = True
#            continue

        # Collect failed login lines
        if inside_failed_block and "# END ANSIBLE MANAGED BLOCK" not in line:
            if line:  # skip empty lines
                failed_logins.append(line)

        # End failed login block
        if "# END ANSIBLE MANAGED BLOCK" in line:
            inside_failed_block = False

        # Print row once we have host + port (end of host block)
        if host and port:
            failed_display = "; ".join(failed_logins) if failed_logins else "-"
            print("{0:<35} {1:<10} {2:<20} {3:<20} {4:<20} {5:<12} {6:<15} {7}".format(
                host, user, last_change, expire,
                permit or "Not set", port, speed or "-", failed_display
            ))
            # Reset
            host = user = last_change = expire = permit = port = speed = ""
            failed_logins = []
            inside_failed_block = False
