#!/bin/bash
set -euo pipefail

echo "[*] Linux lab setup starting..."

########################################
# 1) Fake log structure for Task 2
########################################

echo "[*] Creating fake log files under /var/log/platform..."

mkdir -p /var/log/platform

# Create multiple days and multiple files per day for both app and jira
for day in 01 02 03 04 05 06 07; do
  for app in app jira; do
    for i in 1 2 3 4 5; do
      touch "/var/log/platform/${app}-2025-01-${day}-${i}.log"
    done
  done
done

# Add some ERROR lines into a subset of jira logs
echo "2025-01-02 10:00:00 ERROR Something broke" >> /var/log/platform/jira-2025-01-02-1.log
echo "2025-01-03 11:00:00 ERROR Another failure" >> /var/log/platform/jira-2025-01-03-2.log

########################################
# 2) /opt/app files with varied timestamps
########################################

echo "[*] Creating /opt/app files with varied timestamps..."

mkdir -p /opt/app

# Old files
touch -d "5 days ago" /opt/app/old_config.conf
touch -d "3 days ago" /opt/app/old_data.dat

# Recent files
touch -d "1 day ago" /opt/app/recent_release.bin
touch -d "1 hour ago" /opt/app/recent_hotfix.patch

########################################
# 3) Simulated Jira directory & broken permissions
########################################

echo "[*] Creating simulated Jira directories and breaking permissions..."

# Simulated Jira install dir
mkdir -p /opt/jira/logs
touch /opt/jira/logs/catalina.out

# Simulated Jira home/data dir
mkdir -p /var/atlassian/application-data/jira/{log,plugins,temp}
touch /var/atlassian/application-data/jira/log/atlassian-jira.log

# Break ownership and permissions (Challenge 2)
chown -R root:root /var/atlassian/application-data/jira
chmod 500 /var/atlassian/application-data/jira/log
chmod 500 /var/atlassian/application-data/jira/plugins

########################################
# 4) SSH misconfiguration for Challenge 1
########################################

echo "[*] Setting up SSH AllowGroups misconfiguration..."

# Create sshusers group if not exists
if ! getent group sshusers >/dev/null 2>&1; then
  groupadd sshusers
fi

# Append AllowGroups only if not already present
if ! grep -q '^AllowGroups sshusers' /etc/ssh/sshd_config; then
  echo 'AllowGroups sshusers' >> /etc/ssh/sshd_config
fi

# Try to reload sshd (ignore failure in case of non-systemd or different service name)
systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true

########################################
# 5) Broken systemd service for Challenge 3
########################################

echo "[*] Creating broken systemd service definition..."

cat <<'EOF' >/etc/systemd/system/platform-sync.service
[Unit]
Description=Platform Sync Service

[Service]
User=svc-pIatform
Group=platform-admins
ExecStart=/usr/bin/bash -c "echo 'syncing...' >> /var/lib/platform/sync.log"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload || true

########################################
# 6) Dummy CA certs for keytool task (Task 3)
########################################

echo "[*] Generating dummy CA and server certificates in /tmp..."

# Simple self-signed certs; good enough for keytool import
# ca-root.pem, ca-intermediate.pem, jira-signed.pem

openssl req -x509 -newkey rsa:2048 -keyout /tmp/ca-root.key -out /tmp/ca-root.pem \
  -days 365 -nodes -subj "/CN=LabRootCA" >/dev/null 2>&1

openssl req -x509 -newkey rsa:2048 -keyout /tmp/ca-intermediate.key -out /tmp/ca-intermediate.pem \
  -days 365 -nodes -subj "/CN=LabIntermediateCA" >/dev/null 2>&1

openssl req -x509 -newkey rsa:2048 -keyout /tmp/jira-signed.key -out /tmp/jira-signed.pem \
  -days 365 -nodes -subj "/CN=jira.test.local" >/dev/null 2>&1

echo "[*] Lab setup complete."
echo "[*] Reminder: candidate will create users/groups, /var/lib/platform, and fix all the broken parts."

########################################
# Additional directories for Task 6 (Disk Cleanup)
########################################

echo "[*] Creating simulated Jira cache/temp directories for Task 6..."

mkdir -p /var/atlassian/application-data/jira/caches
mkdir -p /var/atlassian/application-data/jira/temp

# Fill them with dummy files to simulate size
for i in {1..50}; do
    dd if=/dev/zero of=/var/atlassian/application-data/jira/caches/cachefile_$i bs=1K count=50 2>/dev/null
    dd if=/dev/zero of=/var/atlassian/application-data/jira/temp/tmpfile_$i bs=1K count=50 2>/dev/null
done
########################################
# Shell history: sane defaults, no prompt breakage
########################################

echo "[*] Setting up shell history behaviour..."

cat <<'EOF' >/etc/profile.d/history-settings.sh
# Increase history sizes
HISTSIZE=5000
HISTFILESIZE=10000

# Add timestamps to each command in history
HISTTIMEFORMAT='%F %T '

# Do not ignore commands starting with space, but ignore exact duplicates
HISTCONTROL=ignoredups

# Append to the history file, don't overwrite it on each shell exit
shopt -s histappend

# After each command, append it to the history file
# (no recursive PROMPT_COMMAND, keep it simple and stable)
PROMPT_COMMAND='history -a'
EOF
########################################
# SSH: AllowGroups + change port to 24
########################################

echo "[*] Configuring SSH AllowGroups and Port..."

# Ensure sshusers group exists
if ! getent group sshusers >/dev/null 2>&1; then
  groupadd sshusers
fi

# Make sure root is in sshusers (so you don't lock yourself out)
usermod -aG sshusers root

SSHD_CONFIG="/etc/ssh/sshd_config"

# If an AllowGroups line exists (commented or not), replace it.
if grep -qiE '^[[:space:]]*#?[[:space:]]*AllowGroups' "$SSHD_CONFIG"; then
    sed -i 's/^[[:space:]]*#\?[[:space:]]*AllowGroups.*/AllowGroups sshusers/' "$SSHD_CONFIG"
else
    # Insert at line 39, without modifying existing line content.
    # If the file has fewer than 39 lines, it will still work (appends at end).
    awk -v insert="AllowGroups sshusers" -v line=39 '
        NR==line { print insert }
        { print }
        END {
            # If file was shorter than line 39, ensure the insert appears exactly once.
            if (NR < line) print insert
        }
    ' "$SSHD_CONFIG" > "$SSHD_CONFIG.tmp" && mv "$SSHD_CONFIG.tmp" "$SSHD_CONFIG"
fi

# Replace any existing (even commented) Port line with Port 24
if grep -qE '^[[:space:]]*#?[[:space:]]*Port[[:space:]]+' "$SSHD_CONFIG"; then
  sed -i 's/^[[:space:]]*#\?[[:space:]]*Port[[:space:]]\+.*/Port 24/' "$SSHD_CONFIG"
else
  echo 'Port 24' >> "$SSHD_CONFIG"
fi

# Reload/restart SSH
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true

########################################
# Cleanup: remove any existing shell history
########################################

echo "[*] Clearing existing shell history files..."

# Root's history
rm -f /root/.bash_history 2>/dev/null || true

# Any existing user histories (UID >= 1000 are normal users)
awk -F: '$3 >= 1000 {print $6}' /etc/passwd | while read -r HOME; do
  if [ -n "$HOME" ] && [ -d "$HOME" ]; then
    rm -f "$HOME/.bash_history" 2>/dev/null || true
  fi
done

# Also clear skeleton history if present
rm -f /etc/skel/.bash_history 2>/dev/null || true
########################################
# 7) Final reminders for lab owner
########################################


echo
echo "============================================================"
echo " LAB SETUP COMPLETE - MANUAL CHECKLIST / REMINDERS"
echo "============================================================"
echo "1) Install Java (e.g. OpenJDK) so that 'keytool' exists."
echo "   - Typical locations include:"
echo "     /usr/lib/jvm/java-17-openjdk/bin/keytool"
echo "   - Do NOT add 'keytool' to PATH."
echo "     The candidate must locate it and create a symlink."
echo
echo "2) Ensure 'openssl' is installed."
echo "   - This script used openssl to generate dummy certs:"
echo "     /tmp/ca-root.pem"
echo "     /tmp/ca-intermediate.pem"
echo "     /tmp/jira-signed.pem"
echo
echo "3) Confirm the system uses systemd and an SSH service named:"
echo "   - 'sshd' or 'ssh'"
echo "   The script tried: systemctl reload sshd || systemctl reload ssh"
echo
echo "4) DO NOT pre-create these users or groups:"
echo "   - Users: alice, bob, charlie, svc-platform"
echo "   - Groups: platform-admins, platform-devs"
echo "   - Directory: /var/lib/platform"
echo "   These are part of the candidate's Task 1."
echo
echo "5) Candidate tasks will also create:"
echo "   - /etc/pki/jira.keystore (via keytool)"
echo "   - Symlink: /usr/local/bin/keytool -> actual keytool path"
echo
echo "6) If you want to clean up after the exam, consider:"
echo "   - rm -rf /var/log/platform /opt/app /opt/jira"
echo "   - rm -rf /var/atlassian/application-data/jira"
echo "   - rm -f  /etc/systemd/system/platform-sync.service"
echo "   - systemctl daemon-reload"
echo "   - rm -f  /tmp/ca-root.* /tmp/ca-intermediate.* /tmp/jira-signed.*"
echo "============================================================"
echo "[*] Linux lab environment ready for candidate."
