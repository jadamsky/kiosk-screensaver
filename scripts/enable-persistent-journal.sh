#!/bin/bash
# Enable persistent systemd journal logging
# Raspberry Pi OS keeps the journal in RAM only (Storage=volatile), so every
# reboot or power cut erases the logs of the boot before it - including
# whatever went wrong. This keeps logs on disk, with a size cap.

set -e

DROPIN_DIR="/etc/systemd/journald.conf.d"
DROPIN_FILE="$DROPIN_DIR/90-kiosk-persistent.conf"

echo "=========================================="
echo "  Enable Persistent Journal"
echo "=========================================="
echo
echo "This script will:"
echo "1. Create $DROPIN_FILE (Storage=persistent, 200MB cap)"
echo "2. Restart systemd-journald and move current logs to disk"
echo

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   echo "⚠ Please do not run as root. Run as regular user with sudo access."
   exit 1
fi

# Raspberry Pi OS sets Storage=volatile in a drop-in under
# /usr/lib/systemd/journald.conf.d/ (40-rpi-volatile-storage.conf). Drop-ins
# override journald.conf itself, so the setting has to go in a drop-in too,
# named to sort after it so it wins.
echo "Creating journald drop-in..."
sudo mkdir -p "$DROPIN_DIR"
sudo tee "$DROPIN_FILE" > /dev/null <<'EOF'
# Keep the journal on disk so logs survive reboots and power cuts.
# Overrides Raspberry Pi OS's 40-rpi-volatile-storage.conf.
[Journal]
Storage=persistent
SystemMaxUse=200M
EOF
echo "✓ Created $DROPIN_FILE"

# journald creates /var/log/journal itself with Storage=persistent, but make
# sure it exists with the standard ownership
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal

echo
echo "Restarting systemd-journald..."
sudo systemctl restart systemd-journald
# Move this boot's in-memory logs to disk so they aren't lost either
sudo journalctl --flush
echo "✓ systemd-journald restarted"

# Verify
echo
echo "=========================================="
echo "  Verification"
echo "=========================================="
echo
if sudo find /var/log/journal -name '*.journal' | grep -q .; then
    echo "✓ Journal files are being written to /var/log/journal"
    journalctl --disk-usage
else
    echo "✗ No journal files in /var/log/journal yet"
    echo "  Check: systemd-analyze cat-config systemd/journald.conf"
    exit 1
fi

echo
echo "=========================================="
echo "✓ Persistent Journal Enabled"
echo "=========================================="
echo
echo "Logs now survive reboots. After the next reboot:"
echo "  journalctl --list-boots     list recorded boots"
echo "  journalctl -b -1            logs from the previous boot"
