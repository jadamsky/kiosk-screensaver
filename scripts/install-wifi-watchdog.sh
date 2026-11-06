#!/bin/bash
# Install the Wi-Fi watchdog service
# Reconnects wlan0 automatically if it loses its address or can't reach the
# gateway (e.g. NetworkManager gave up after the access point rejected it
# at boot). Safe to re-run: it just updates the script and restarts the service.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHDOG_SRC="$SCRIPT_DIR/wifi-watchdog.py"
WATCHDOG_BIN="/usr/local/bin/wifi-watchdog.py"
SERVICE_FILE="/etc/systemd/system/wifi-watchdog.service"

echo "=========================================="
echo "  Install Wi-Fi Watchdog"
echo "=========================================="
echo
echo "This script will:"
echo "1. Install $WATCHDOG_BIN"
echo "2. Create and enable wifi-watchdog.service"
echo "3. Start (or restart) the service now"
echo

# Check if running as root
if [ "$EUID" -eq 0 ]; then
   echo "⚠ Please do not run as root. Run as regular user with sudo access."
   exit 1
fi

if [ ! -f "$WATCHDOG_SRC" ]; then
    echo "✗ Watchdog script not found: $WATCHDOG_SRC"
    exit 1
fi

if ! command -v nmcli &> /dev/null; then
    echo "✗ nmcli not found - this watchdog requires NetworkManager"
    exit 1
fi

# Install the script root-owned, so the root service never runs a user-writable file
echo "Installing watchdog script..."
sudo install -m 0755 -o root -g root "$WATCHDOG_SRC" "$WATCHDOG_BIN"
echo "✓ Installed $WATCHDOG_BIN"

# Create systemd service
echo
echo "Creating systemd service..."
sudo tee "$SERVICE_FILE" > /dev/null <<'EOF'
[Unit]
Description=Wi-Fi watchdog (reconnect wlan0 if the link drops)
After=NetworkManager.service
Wants=NetworkManager.service
# Never stop restarting it, however often it exits
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/wifi-watchdog.py
Restart=always
RestartSec=5
Nice=10
# Optional: pin the NetworkManager profile (name or UUID) to reconnect
#Environment=WIFI_WATCHDOG_CONNECTION=MyNetwork

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and (re)start service
sudo systemctl daemon-reload
sudo systemctl enable wifi-watchdog.service 2>/dev/null && {
    echo "✓ Wi-Fi watchdog service enabled (will run on boot)"
} || {
    echo "⚠ Failed to enable service"
    exit 1
}
sudo systemctl restart wifi-watchdog.service

# Verify current status
echo
echo "=========================================="
echo "  Verification"
echo "=========================================="
echo
sleep 2
if systemctl is-active --quiet wifi-watchdog.service; then
    echo "✓ wifi-watchdog.service is running"
else
    echo "✗ wifi-watchdog.service is not running"
    echo "  Check logs: journalctl -u wifi-watchdog -n 50"
    exit 1
fi
echo -n "Current link check: "
sudo /usr/bin/python3 "$WATCHDOG_BIN" --check || true

echo
echo "=========================================="
echo "✓ Wi-Fi Watchdog Installed Successfully"
echo "=========================================="
echo
echo "Checks wlan0 every 30 seconds and reconnects if it is down."
echo "View activity:  journalctl -u wifi-watchdog"
echo "One-shot check: sudo python3 $WATCHDOG_BIN --check"
echo "Pause it:       sudo systemctl stop wifi-watchdog"
