#!/bin/bash
# Screensaver complete uninstall - removes ALL screensaver components

echo "=========================================="
echo "Screensaver Complete Uninstall"
echo "=========================================="
echo ""

# 1. Stop and remove systemd services
echo "[1/7] Stopping systemd services..."
if systemctl is-active screensaver-web.service >/dev/null 2>&1; then
    sudo systemctl stop screensaver-web.service
    echo "✓ Web admin service stopped"
fi
if systemctl is-enabled screensaver-web.service >/dev/null 2>&1; then
    sudo systemctl disable screensaver-web.service
    echo "✓ Web admin service disabled"
fi
if [ -f /etc/systemd/system/screensaver-web.service ]; then
    sudo rm -f /etc/systemd/system/screensaver-web.service
    sudo systemctl daemon-reload
    echo "✓ Web admin service removed"
fi
if [ -f /etc/systemd/system/wifi-watchdog.service ]; then
    sudo systemctl disable --now wifi-watchdog.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/wifi-watchdog.service /usr/local/bin/wifi-watchdog.py
    sudo systemctl daemon-reload
    echo "✓ WiFi watchdog service removed"
fi
# Persistent logging (/etc/systemd/journald.conf.d/90-kiosk-persistent.conf)
# is left in place - it is harmless and keeps logs useful after uninstall

# 2. Kill screensaver processes
echo "[2/7] Stopping screensaver processes..."
pkill -f screensaver.main 2>/dev/null || true
pkill -f screensaver.web.app 2>/dev/null || true
pkill -f chromium.*slideshow.html 2>/dev/null || true
pkill -f chromium.*screensaver.html 2>/dev/null || true
echo "✓ Screensaver processes stopped"

# 3. Remove screensaver from labwc autostart - COMPLETE REMOVAL
echo "[3/7] Removing labwc configuration..."
if [ -f ~/.config/labwc/autostart ]; then
    # The installer completely owns the autostart file, so remove it entirely
    rm -f ~/.config/labwc/autostart
    echo "✓ Autostart file removed"
fi

# Remove other labwc configuration files
if [ -f ~/.config/labwc/rc.xml ]; then
    rm -f ~/.config/labwc/rc.xml
    echo "✓ rc.xml removed"
fi
if [ -f ~/.config/labwc/environment ]; then
    rm -f ~/.config/labwc/environment
    echo "✓ environment file removed"
fi

# 4. Remove libinput quirks
echo "[4/7] Removing touchscreen quirks..."
if [ -f /etc/libinput/local-overrides.quirks ]; then
    sudo rm -f /etc/libinput/local-overrides.quirks
    echo "✓ Touchscreen quirks removed"
fi

# 5. Remove screensaver installation directory
echo "[5/7] Removing screensaver installation..."
rm -rf ~/kiosk-screensaver
echo "✓ Installation directory removed"

# 6. Remove screensaver data files
echo "[6/7] Removing screensaver data files..."
rm -f ~/photo-list.json
rm -f ~/.ha_token
rm -f ~/kiosk-screensaver.log
rm -f ~/screensaver-startup.log
echo "✓ Data files removed"

# 7. Clean up screensaver temp directories
echo "[7/7] Cleaning temporary files..."
rm -rf /tmp/chromium-slideshow
rm -rf /tmp/chromium-screensaver-night
echo "✓ Temporary files removed"

echo ""
echo "=========================================="
echo "Screensaver uninstall complete!"
echo "=========================================="
echo ""
echo "Your system's existing configuration has been preserved."
echo "Dashboard autostart and other settings remain unchanged."
echo ""
echo "To install fresh screensaver:"
echo "  1. Transfer kiosk-screensaver folder to ~/kiosk-screensaver"
echo "  2. Fix line endings: find ~/kiosk-screensaver -name \"*.sh\" -exec sed -i 's/\r$//' {} \;"
echo "  3. Edit config: nano ~/kiosk-screensaver/config.yaml"
echo "  4. Run: cd ~/kiosk-screensaver && bash install.sh"
echo ""
