import pymysql
from pymysql.cursors import DictCursor
import subprocess
from datetime import date, timedelta
import os
import re
import sys

# --- Config ---
backup_dir = "/data/dbbackup"
zip_password = "B@CkU9i9d"
mysql_root_user = "root"
mysql_root_pass = "1G8323AuR$"
log_file = "/var/log/db_restore.log"

# --- Logging function ---
def log(msg):
    timestamp = date.today().strftime("%Y-%m-%d")
    with open(log_file, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")
    print(f"[{timestamp}] {msg}")

# --- Helper to check gzip ---
def is_valid_gzip(file_path):
    try:
        subprocess.check_call(f"gzip -t '{file_path}'", shell=True,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except subprocess.CalledProcessError:
        return False

# --- Connect to tracker DB ---
try:
    tracker_conn = pymysql.connect(
        host="172.16.16.108",
        user=mysql_root_user,
        password=mysql_root_pass,
        database="restore_tracker_db",
        cursorclass=DictCursor
    )
    cursor = tracker_conn.cursor()
    log("Connected to tracker DB.")
except Exception as e:
    log(f"Failed to connect to tracker DB: {e}")
    sys.exit(1)

# --- Date strings for yesterday and today ---
yesterday = date.today() - timedelta(days=1)
today = date.today()

yesterday_iso = yesterday.strftime("%Y-%m-%d")
today_iso = today.strftime("%Y-%m-%d")

yesterday_alt = yesterday.strftime("%Y%m%d")
today_alt = today.strftime("%Y%m%d")

# --- Patterns ---
pattern_gz = re.compile(r"^(?P<dbname>.+)_(?P<date>\d{4}-\d{2}-\d{2})\.sql\.gz$")
pattern_zip = re.compile(r"^(?P<dbname>.+)_(?P<date>\d{4}-\d{2}-\d{2})\.sql\.zip$")

# --- Step 1: Find yesterday & today backups not yet in tracker ---
cursor.execute("SELECT db_name, backup_date FROM db_restore_tracker WHERE backup_date IN (%s, %s)", 
               (yesterday_iso, today_iso))
already_added = {(row["db_name"], str(row["backup_date"])) for row in cursor.fetchall()}

new_entries = []
for fname in sorted(os.listdir(backup_dir)):
    db_name, fpath, file_type, backup_date = None, None, None, None

    # Check .gz
    mgz = pattern_gz.match(fname)
    if mgz and mgz.group("date") in (yesterday_iso, today_iso):
        db_name = mgz.group("dbname")
        backup_date = mgz.group("date")
        fpath = os.path.join(backup_dir, fname)
        file_type = "gz"

    # Check .zip
    mzip = pattern_zip.match(fname)
    if mzip and mzip.group("date") in (yesterday_iso, today_iso):
        db_name = mzip.group("dbname")
        backup_date = mzip.group("date")
        fpath = os.path.join(backup_dir, fname)
        file_type = "zip"

    if not db_name or not fpath or (db_name, backup_date) in already_added:
        continue

    new_entries.append((db_name, fpath, file_type, backup_date))
    if len(new_entries) >= 5:
        break

log(f"Pending new entries: {[db for db, _, _, _ in new_entries]}")

# --- Step 2: Insert pending entries ---
for db_name, fpath, file_type, backup_date in new_entries:
    log(f"Inserting pending entry for {db_name} ({backup_date})")
    cursor.execute(
        "INSERT INTO db_restore_tracker (db_name, restore_status, backup_date) VALUES (%s, 'pending', %s)",
        (db_name, backup_date)
    )
tracker_conn.commit()

# --- Step 3: Process pending entries ---
cursor.execute("SELECT * FROM db_restore_tracker WHERE restore_status='pending' LIMIT 5")
projects = cursor.fetchall()
log(f"Found {len(projects)} pending project(s).")

tmp_dir = "/tmp/dbrestore"
os.makedirs(tmp_dir, exist_ok=True)

for project in projects:
    db_name = project["db_name"]
    backup_date = str(project["backup_date"])
    backup_file, file_type = None, None

    # Find matching file
    for fname in os.listdir(backup_dir):
        # .gz exact match
        if fname.startswith(f"{db_name}_{backup_date}") and fname.endswith(".sql.gz"):
            backup_file = os.path.join(backup_dir, fname)
            file_type = "gz"
            break
        # .zip match for YYYY-MM-DD or YYYYMMDD
        elif (fname.startswith(f"{db_name}_{backup_date}") or
              fname.startswith(f"{db_name}_{backup_date.replace('-', '')}")) and fname.endswith(".sql.zip"):
            backup_file = os.path.join(backup_dir, fname)
            file_type = "zip"
            break

    if not backup_file:
        log(f"Backup file not found for {db_name} ({backup_date})")
        continue

    log(f"Processing database: {db_name} (date: {backup_date})")
    log(f"Found backup file: {backup_file}")

    sql_file = os.path.join(tmp_dir, db_name + ".sql")

    # --- Extract SQL ---
    try:
        if file_type == "gz":
            if is_valid_gzip(backup_file):
                subprocess.check_call(f"gunzip -c '{backup_file}' > '{sql_file}'", shell=True)
            else:
                log(f"Warning: {backup_file} is not a valid gzip. Copying as plain SQL.")
                subprocess.check_call(f"cp '{backup_file}' '{sql_file}'", shell=True)
        elif file_type == "zip":
            subprocess.check_call(f"unzip -o -P '{zip_password}' '{backup_file}' -d '{tmp_dir}'", shell=True)
            # Find extracted SQL file
            for root, dirs, files in os.walk(tmp_dir):
                for f in files:
                    if f.endswith(".sql") and f.startswith(db_name):
                        sql_file = os.path.join(root, f)
                        break
        if not os.path.exists(sql_file):
            raise FileNotFoundError("SQL file not found after extraction")
    except Exception as e:
        log(f"Extraction failed for {db_name}: {e}")
        cursor.execute(
            "UPDATE db_restore_tracker SET restore_status='failed', health_status='corrupted' WHERE db_name=%s AND backup_date=%s",
            (db_name, backup_date)
        )
        tracker_conn.commit()
        continue

    # --- Create DB ---
    try:
        subprocess.check_call(f"mysql -u{mysql_root_user} -p'{mysql_root_pass}' -e 'CREATE DATABASE IF NOT EXISTS `{db_name}`'", shell=True)
        log(f"Database created: {db_name}")
    except Exception as e:
        log(f"DB creation failed for {db_name}: {e}")

    # --- Restore DB ---
    try:
        subprocess.check_call(f"mysql -u{mysql_root_user} -p'{mysql_root_pass}' {db_name} < '{sql_file}'", shell=True)
        restore_status = "success"
        log(f"Restore completed for {db_name}")
    except subprocess.CalledProcessError as e:
        restore_status = "failed"
        log(f"Restore failed for {db_name}: {e}")

    # --- Health check ---
    health_status = "not_checked"
    if restore_status == "success":
        try:
            db_conn = pymysql.connect(
                host="localhost",
                user=mysql_root_user,
                password=mysql_root_pass,
                database=db_name
            )
            health_cursor = db_conn.cursor()
            health_cursor.execute("SHOW TABLES")
            tables = health_cursor.fetchall()
            health_status = "healthy" if tables else "corrupted"
            db_conn.close()
            log(f"Health check: {db_name} -> {health_status}")
        except Exception as e:
            health_status = "corrupted"
            log(f"Health check failed for {db_name}: {e}")

    # --- Update tracker ---
    cursor.execute("""
        UPDATE db_restore_tracker 
        SET restore_status=%s, health_status=%s 
        WHERE db_name=%s AND backup_date=%s
    """, (restore_status, health_status, db_name, backup_date))
    tracker_conn.commit()
    log(f"Tracker updated for {db_name} ({backup_date})")

# --- Cleanup ---
try:
    subprocess.call(f"rm -rf '{tmp_dir}'/*", shell=True)
    log("Temporary files cleaned up.")
except Exception as e:
    log(f"Failed to clean temporary files: {e}")

cursor.close()
tracker_conn.close()
log("All done.")