#!/bin/bash
# Installation script for Kiosk Screensaver
# For Raspberry Pi 5 running Raspberry Pi OS (64-bit) Debian Trixie or newer
#
# PREREQUISITES:
# - Fresh Raspberry Pi OS (64-bit) installation
# - Currently configured to boot into Desktop with auto-login
# - This script will:
#   1. Install required dependencies (labwc, ddcutil, wlopm, chromium, etc.)
#   2. Switch boot mode from Desktop to CLI
#   3. Configure labwc Wayland compositor to auto-start
#   4. Set up Home Assistant dashboard in kiosk mode
#   5. Install and configure screensaver system
#
# RECOMMENDED HARDWARE:
# - Raspberry Pi 5 (8GB RAM recommended)
# - DDC/CI-compliant monitor for brightness control
#   (Most modern monitors support DDC/CI, but not all)
#
# INSTALLATION:
# 1. Transfer this folder to ~/kiosk-screensaver on your Pi
# 2. Fix line endings if transferring from Windows:
#    find ~/kiosk-screensaver -name "*.sh" -exec sed -i 's/\r$//' {} \;
# 3. Run this script:
#    cd ~/kiosk-screensaver
#    bash install.sh

set -e

# Get current user and home directory
CURRENT_USER="$USER"
USER_HOME="$HOME"
INSTALL_DIR="$USER_HOME/kiosk-screensaver"
CONFIG_TEMPLATE="$INSTALL_DIR/config.yaml.template"
CONFIG_FILE="$INSTALL_DIR/config.yaml"

echo "========================================================"
echo "   Kiosk Screensaver Installation Script"
echo "   For Raspberry Pi 5 + Raspberry Pi OS (64-bit)"
echo "========================================================"
echo
echo "Installation directory: $INSTALL_DIR"
echo "User: $CURRENT_USER"
echo "Home: $USER_HOME"
echo

# Confirmation prompt
read -p "This will modify your system configuration. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 1
fi

# ==============================================================================
# STEP 1: Install system dependencies
# ==============================================================================
echo
echo "========================================================"
echo "STEP 1/10: Installing System Dependencies"
echo "========================================================"
echo
echo "This will install:"
echo "  - labwc (Wayland compositor)"
echo "  - ddcutil (monitor brightness control via DDC/CI)"
echo "  - wlopm (Wayland output power management)"
echo "  - chromium (web browser for dashboard and slideshow)"
echo "  - rclone (file serving)"
echo "  - iw (WiFi power management control)"
echo "  - python3 and pip"
echo

read -p "Install dependencies? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "Updating package lists..."
    sudo apt-get update

    echo "Installing packages..."
    sudo apt-get install -y \
        labwc \
        ddcutil \
        chromium \
        rclone \
        iw \
        python3 \
        python3-pip \
        procps \
        i2c-tools \
        unclutter

    # Check if wlopm is installed
    if ! command -v wlopm &> /dev/null; then
        echo
        echo "⚠ wlopm not found in repositories"
        echo "  You may need to install it manually from:"
        echo "  https://git.sr.ht/~leon_plickat/wlopm"
        echo
        read -p "Continue without wlopm? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    echo "✓ System dependencies installed"

    # Downgrade Chromium to stable version 142.0.7444.175
    # Chromium 143+ has severe stability issues on Raspberry Pi 5
    # https://forums.raspberrypi.com/viewtopic.php?t=308303
    echo
    echo "Downgrading Chromium to stable version 142.0.7444.175..."
    CURRENT_CHROMIUM=$(chromium --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' || echo "unknown")
    echo "Current Chromium version: $CURRENT_CHROMIUM"

    if [[ "$CURRENT_CHROMIUM" != "142.0.7444.175" ]]; then
        echo "Downloading Chromium 142.0.7444.175 packages..."
        cd /tmp
        wget -q http://archive.raspberrypi.org/debian/pool/main/c/chromium/chromium_142.0.7444.175-1~deb13u1+rpt1_arm64.deb
        wget -q http://archive.raspberrypi.org/debian/pool/main/c/chromium/chromium-common_142.0.7444.175-1~deb13u1+rpt1_arm64.deb
        wget -q http://archive.raspberrypi.org/debian/pool/main/c/chromium/chromium-sandbox_142.0.7444.175-1~deb13u1+rpt1_arm64.deb

        echo "Installing Chromium 142.0.7444.175..."
        sudo apt install -y --allow-downgrades \
            ./chromium_142.0.7444.175-1~deb13u1+rpt1_arm64.deb \
            ./chromium-common_142.0.7444.175-1~deb13u1+rpt1_arm64.deb \
            ./chromium-sandbox_142.0.7444.175-1~deb13u1+rpt1_arm64.deb

        echo "Holding Chromium at version 142.0.7444.175 (prevents auto-update)..."
        sudo apt-mark hold chromium chromium-common chromium-sandbox

        rm -f /tmp/chromium*.deb
        echo "✓ Chromium downgraded to 142.0.7444.175 and held"
    else
        echo "✓ Chromium already at stable version 142.0.7444.175"
        sudo apt-mark hold chromium chromium-common chromium-sandbox 2>/dev/null || true
    fi

    # Disable Plymouth boot splash screen (prevents bright white screen during night reboots)
    echo
    echo "Disabling Plymouth boot splash screen..."
    if dpkg -l | grep -q plymouth; then
        sudo systemctl disable plymouth.service 2>/dev/null || true
        sudo systemctl mask plymouth.service 2>/dev/null || true
        sudo apt-get remove -y plymouth plymouth-themes 2>/dev/null || true
        sudo update-initramfs -u 2>/dev/null || true
        echo "✓ Plymouth boot splash disabled"
    else
        echo "✓ Plymouth not installed, skipping"
    fi
else
    echo "Skipping dependency installation"
fi

# ==============================================================================
# STEP 2: Verify dependencies
# ==============================================================================
echo
echo "========================================================"
echo "STEP 2/10: Verifying Dependencies"
echo "========================================================"
MISSING_DEPS=()
for cmd in python3 pip3 chromium ddcutil rclone pgrep pkill labwc; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_DEPS+=($cmd)
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "✗ Error: Missing required commands: ${MISSING_DEPS[*]}"
    echo
    echo "Please install them manually and run this script again."
    exit 1
fi

echo "✓ All required dependencies found"

# ==============================================================================
# STEP 3: Configure boot mode (Desktop -> CLI)
# ==============================================================================
echo
echo "========================================================"
echo "STEP 3/10: Configuring Boot Mode"
echo "========================================================"
echo
echo "Your system is currently configured to boot into Desktop mode."
echo "For a kiosk setup, we need to:"
echo "  1. Switch to CLI (console) boot mode"
echo "  2. Keep auto-login enabled"
echo "  3. Configure labwc to start automatically"
echo
read -p "Switch boot mode to CLI? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "Configuring boot to CLI with auto-login..."
    # Use raspi-config nonint to set boot mode
    # B2 = Console Autologin (text console, automatically logged in as current user)
    sudo raspi-config nonint do_boot_behaviour B2
    echo "✓ Boot mode set to CLI with auto-login"
else
    echo "⚠ Skipping boot mode configuration"
    echo "  Note: You may need to manually configure this for proper operation"
fi

# ==============================================================================
# STEP 4: Collect user configuration
# ==============================================================================
echo
echo "========================================================"
echo "STEP 4/10: Configuration Setup"
echo "========================================================"
echo

# Home Assistant URL
echo "--- Home Assistant Configuration ---"
echo
read -p "Do you want to enable Home Assistant integration? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    HA_ENABLED="false"
    HA_URL=""
    echo "Home Assistant integration disabled"
else
    HA_ENABLED="true"
    echo "Enter your Home Assistant URL (including https:// and port)"
    echo "Example: https://192.168.1.100:8123"
    echo
    echo "IMPORTANT: Use your LOCAL network IP address, NOT DuckDNS or external URL"
    echo "The screensaver runs on the same local network as Home Assistant"
    read -p "HA URL: " HA_URL
    echo "✓ Home Assistant URL: $HA_URL"
fi

# Dashboard URL
echo
echo "--- Dashboard Configuration ---"
echo
echo "Enter your kiosk dashboard URL (this will open in Chromium kiosk mode)"
echo "This can be the same as your Home Assistant URL, or a different dashboard"
echo "Example: https://192.168.1.100:8123"
echo
echo "IMPORTANT: Use your LOCAL network IP address, NOT DuckDNS or external URL"
echo "External URLs may cause connectivity issues or slow loading"
read -p "Dashboard URL: " DASHBOARD_URL
echo "✓ Dashboard URL: $DASHBOARD_URL"

# Photo source path
echo
echo "--- Photo Source Configuration ---"
echo
echo "Enter the path to your photos folder"
echo "Examples:"
echo "  Local folder: /home/$CURRENT_USER/Pictures"
echo "  Network mount: /mnt/photos"
echo "  Windows share mount: /mnt/windows-photos"
echo
read -p "Photo path: " PHOTO_PATH

# Expand ~ to actual home directory
PHOTO_PATH="${PHOTO_PATH/#\~/$USER_HOME}"

if [ -d "$PHOTO_PATH" ]; then
    PHOTO_COUNT=$(find "$PHOTO_PATH" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) 2>/dev/null | wc -l)
    echo "✓ Photo path exists: $PHOTO_PATH"
    echo "  Found approximately $PHOTO_COUNT photo files"
else
    echo "⚠ Warning: Photo path does not exist: $PHOTO_PATH"
    echo "  You can mount it later before starting the screensaver"
fi

# ==============================================================================
# STEP 5: Generate configuration file
# ==============================================================================
echo
echo "========================================================"
echo "STEP 5/10: Generating Configuration File"
echo "========================================================"

# Create config from template
if [ ! -f "$CONFIG_TEMPLATE" ]; then
    echo "✗ Error: Template file not found: $CONFIG_TEMPLATE"
    exit 1
fi

cp "$CONFIG_TEMPLATE" "$CONFIG_FILE"

# Replace placeholders
sed -i "s|__INSTALL_DIR__|$INSTALL_DIR|g" "$CONFIG_FILE"
sed -i "s|__PHOTO_PATH__|$PHOTO_PATH|g" "$CONFIG_FILE"
sed -i "s|__HA_ENABLED__|$HA_ENABLED|g" "$CONFIG_FILE"
sed -i "s|__HA_URL__|$HA_URL|g" "$CONFIG_FILE"
sed -i "s|__DASHBOARD_URL__|$DASHBOARD_URL|g" "$CONFIG_FILE"

echo "✓ Configuration file created: $CONFIG_FILE"

# ==============================================================================
# STEP 6: Install Python dependencies
# ==============================================================================
echo
echo "========================================================"
echo "STEP 6/10: Installing Python Dependencies"
echo "========================================================"
pip3 install --user --break-system-packages -r "$INSTALL_DIR/requirements.txt"
echo "✓ Python dependencies installed"

# ==============================================================================
# STEP 7: Configure user permissions
# ==============================================================================
echo
echo "========================================================"
echo "STEP 7/10: Configuring User Permissions"
echo "========================================================"

# Add user to input group for keyboard/mouse monitoring
if ! groups $CURRENT_USER | grep -q '\binput\b'; then
    echo "Adding $CURRENT_USER to 'input' group for device monitoring..."
    sudo usermod -a -G input $CURRENT_USER
    echo "✓ Added to input group (logout required to take effect)"
    NEED_LOGOUT=true
else
    echo "✓ User already in input group"
fi

# Add user to i2c group for DDC/CI monitor control
if ! groups $CURRENT_USER | grep -q '\bi2c\b'; then
    echo "Adding $CURRENT_USER to 'i2c' group for DDC/CI monitor control..."
    sudo usermod -a -G i2c $CURRENT_USER
    echo "✓ Added to i2c group (logout required to take effect)"
    NEED_LOGOUT=true
else
    echo "✓ User already in i2c group"
fi

# Configure sudo permissions for web interface reboot
echo "Configuring sudo permissions for reboot..."
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/sbin/reboot" | sudo tee /etc/sudoers.d/kiosk-screensaver > /dev/null
sudo chmod 0440 /etc/sudoers.d/kiosk-screensaver

# Validate sudoers syntax
if sudo visudo -c -f /etc/sudoers.d/kiosk-screensaver > /dev/null 2>&1; then
    echo "✓ Sudo permissions configured (web interface can trigger reboot)"
else
    echo "⚠ Warning: Sudoers file has syntax errors, removing it"
    sudo rm -f /etc/sudoers.d/kiosk-screensaver
fi

# ==============================================================================
# STEP 8: Install systemd services
# ==============================================================================
echo
echo "========================================================"
echo "STEP 8/10: Installing Systemd Services"
echo "========================================================"

# Create systemd service files with correct paths
cat > /tmp/screensaver.service <<EOF
[Unit]
Description=Kiosk Screensaver
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u $CURRENT_USER)
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 -m screensaver.main -c $INSTALL_DIR/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat > /tmp/screensaver-web.service <<EOF
[Unit]
Description=Kiosk Screensaver Web Admin
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 -m screensaver.web.app $INSTALL_DIR/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "This requires sudo password..."
sudo cp /tmp/screensaver.service /etc/systemd/system/
sudo cp /tmp/screensaver-web.service /etc/systemd/system/
sudo systemctl daemon-reload

rm /tmp/screensaver.service /tmp/screensaver-web.service

echo "✓ Systemd services installed"

# ==============================================================================
# STEP 9: Clear Chromium cache for clean installation
# ==============================================================================
echo
echo "========================================================"
echo "STEP 9/10: Clearing Chromium Cache"
echo "========================================================"

echo "Clearing existing Chromium cache..."
if [ -d "$USER_HOME/.config/chromium" ] || [ -d "$USER_HOME/.cache/chromium" ]; then
    rm -rf "$USER_HOME/.config/chromium" "$USER_HOME/.cache/chromium"
    echo "✓ Chromium cache cleared"
    echo "  This ensures a clean start with new configuration"
else
    echo "✓ No existing Chromium cache found"
fi

# ==============================================================================
# STEP 10: Configure touchscreen for multi-touch
# ==============================================================================
echo
echo "========================================================"
echo "STEP 10/10: Configuring Touchscreen"
echo "========================================================"
echo "Configuring touchscreen for multi-touch mode..."

AUTOSTART_DIR="$USER_HOME/.config/labwc"
AUTOSTART_FILE="$AUTOSTART_DIR/autostart"

# Create labwc config directory if it doesn't exist
mkdir -p "$AUTOSTART_DIR"

# Create or update autostart file
if [ -f "$AUTOSTART_FILE" ]; then
    echo "Updating existing autostart file..."
    # Remove old screensaver entries if present
    sed -i '/screensaver.main/d' "$AUTOSTART_FILE"
    sed -i '/# Kiosk Screensaver/d' "$AUTOSTART_FILE"
    sed -i '/# Home Assistant Dashboard/d' "$AUTOSTART_FILE"
    sed -i '/chromium.*--kiosk/d' "$AUTOSTART_FILE"
else
    echo "Creating new autostart file..."
    touch "$AUTOSTART_FILE"
fi

# Add Home Assistant dashboard (starts first)
cat >> "$AUTOSTART_FILE" <<EOF

# Start gnome-keyring to prevent Chromium password prompts
eval \$(gnome-keyring-daemon --start --components=secrets)
export SSH_AUTH_SOCK

# Set monitor input to HDMI (VCP code 62, value 100 = HDMI)
ddcutil setvcp 62 100 &

# Set VAAPI hardware video decode driver for Pi 5
export LIBVA_DRIVER_NAME=v3d_video

# Hide mouse cursor after 2 seconds of inactivity
unclutter -idle 2 -root &

# Home Assistant Dashboard (Chromium Kiosk Mode)
chromium --kiosk --noerrdialogs --disable-infobars --no-first-run --check-for-update-interval=31536000 --password-store=basic --disable-features=WakeLockSensor,IdleDetection,MediaSession --use-gl=egl --enable-features=VaapiVideoDecoder,VaapiVideoEncoder --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --ignore-certificate-errors $DASHBOARD_URL &

# Kiosk Screensaver (Python version) - log startup to file for debugging
cd $INSTALL_DIR && PYTHONPATH=$INSTALL_DIR python3 -m screensaver.main -c $INSTALL_DIR/config.yaml >> $USER_HOME/screensaver-startup.log 2>&1 &
EOF

echo "✓ labwc autostart configured"
echo "  Dashboard will launch first, then screensaver"

# ==============================================================================
# STEP 7: Configure touchscreen for multi-touch
# ==============================================================================
echo
echo "========================================================"
echo "STEP 7/10: Configuring Touchscreen"
echo "========================================================"
echo "Configuring touchscreen for multi-touch mode..."

# Create libinput quirks directory if it doesn't exist
sudo mkdir -p /etc/libinput

# Create libinput quirks file for persistent touchscreen configuration
sudo tee /etc/libinput/local-overrides.quirks > /dev/null <<'EOF'
[Touchscreen Multi-Touch Configuration]
MatchUdevType=touchscreen
AttrTouchSizeRange=0:0
AttrPressureRange=0:0
AttrPalmPressureThreshold=200

[Enable Finger Tracking]
MatchUdevType=touchscreen
AttrFingerHighPressureThreshold=5
EOF

# Create labwc rc.xml to disable mouse emulation for touchscreen
RC_XML_FILE="$AUTOSTART_DIR/rc.xml"
cat > "$RC_XML_FILE" <<'EOF'
<?xml version="1.0"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
	<touch deviceName="ILITEK       TES, MicroTouch PCT Controller                          EK-TOUCH" mapToOutput="HDMI-A-2" mouseEmulation="no"/>
</openbox_config>
EOF

# Create labwc environment file with keyboard layout
ENVIRONMENT_FILE="$AUTOSTART_DIR/environment"
cat > "$ENVIRONMENT_FILE" <<'EOF'
XKB_DEFAULT_MODEL=pc105
XKB_DEFAULT_LAYOUT=us
XKB_DEFAULT_VARIANT=
XKB_DEFAULT_OPTIONS=
EOF

echo "✓ Touchscreen configured for multi-touch mode"
echo "  libinput quirks: /etc/libinput/local-overrides.quirks"
echo "  labwc rc.xml: $RC_XML_FILE (specific device mapping)"
echo "  labwc environment: $ENVIRONMENT_FILE (keyboard layout)"

# ==============================================================================
# STEP 8: Configure labwc to start on login
# ==============================================================================
# Configure labwc to start on login (tty1 only)
echo
echo "Configuring labwc to start on login..."

# Check if already configured
if grep -q "exec labwc" "$USER_HOME/.bash_profile" 2>/dev/null; then
    echo "✓ labwc auto-start already configured in .bash_profile"
else
    cat >> "$USER_HOME/.bash_profile" <<'EOF'

# Start labwc Wayland compositor on login (tty1 only)
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
  exec labwc
fi
EOF
    echo "✓ labwc will auto-start on console login"
fi

# ==============================================================================
# STEP 9: Disable WiFi Power Save (prevents network dropouts)
# ==============================================================================
echo
echo "========================================================"
echo "STEP 9/12: Disabling WiFi Power Save"
echo "========================================================"
echo
echo "WiFi power save can cause brief network dropouts during:"
echo "  - Wake from screensaver"
echo "  - High CPU/GPU load (photo transitions)"
echo "  - Idle periods"
echo
echo "This step will disable WiFi power management for stability."
echo

# Create systemd service to disable WiFi power save on boot
WIFI_SERVICE_FILE="/etc/systemd/system/disable-wifi-powersave.service"

echo "Creating systemd service to disable WiFi power save..."
sudo tee "$WIFI_SERVICE_FILE" > /dev/null <<'EOF'
[Unit]
Description=Disable WiFi Power Save
After=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
# Disable power management on wlan0
ExecStart=/usr/sbin/iw dev wlan0 set power_save off
# If iw is not available, try iwconfig
ExecStart=-/usr/sbin/iwconfig wlan0 power off

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable disable-wifi-powersave.service 2>/dev/null && {
    echo "✓ WiFi power save disable service enabled (will run on boot)"
} || {
    echo "⚠ Failed to enable WiFi power save disable service"
}

# Disable WiFi power save immediately
echo "Disabling WiFi power save now..."
if command -v iw &> /dev/null; then
    sudo iw dev wlan0 set power_save off 2>/dev/null && {
        echo "✓ WiFi power save disabled (iw command)"
    } || {
        echo "⚠ Could not disable WiFi power save with iw (may not be using WiFi)"
    }
elif command -v iwconfig &> /dev/null; then
    sudo iwconfig wlan0 power off 2>/dev/null && {
        echo "✓ WiFi power save disabled (iwconfig command)"
    } || {
        echo "⚠ Could not disable WiFi power save with iwconfig (may not be using WiFi)"
    }
else
    echo "⚠ Neither iw nor iwconfig found - cannot disable WiFi power save"
    echo "  You may need to install wireless-tools or iw package"
fi

echo
echo "✓ WiFi power save configuration complete"

# ==============================================================================
# STEP 10: WiFi watchdog and persistent logging
# ==============================================================================
echo
echo "========================================================"
echo "STEP 10/12: Installing WiFi Watchdog and Persistent Logging"
echo "========================================================"
echo
echo "If the access point rejects the kiosk at boot, NetworkManager can"
echo "mistake it for a wrong password and stop reconnecting until someone"
echo "intervenes. The watchdog checks WiFi every 30 seconds and reconnects."
echo "Persistent logging keeps system logs across reboots for diagnosis."
echo

bash "$INSTALL_DIR/scripts/enable-persistent-journal.sh" || {
    echo "⚠ Failed to enable persistent logging (system logs will not survive reboots)"
}

bash "$INSTALL_DIR/scripts/install-wifi-watchdog.sh" || {
    echo "⚠ Failed to install WiFi watchdog"
    echo "  Retry later with: bash $INSTALL_DIR/scripts/install-wifi-watchdog.sh"
}

# ==============================================================================
# STEP 11: Generate initial photo list
# ==============================================================================
echo
echo "========================================================"
echo "STEP 11/11: Generating Initial Photo List"
echo "========================================================"

if [ -d "$PHOTO_PATH" ]; then
    echo "Scanning photo directory and generating photo list..."
    cd "$INSTALL_DIR" && PYTHONPATH="$INSTALL_DIR" python3 -m screensaver.photo_manager "$CONFIG_FILE" 2>/dev/null && {
        PHOTO_COUNT=$(python3 -c "import json; print(len(json.load(open('$USER_HOME/photo-list.json'))))" 2>/dev/null || echo "unknown")
        echo "✓ Photo list generated successfully"
        echo "  Found $PHOTO_COUNT photos"
    } || {
        echo "⚠ Failed to generate photo list"
        echo "  This is normal if photos haven't been mounted yet"
        echo "  The screensaver will generate it on first run"
    }
else
    echo "⚠ Photo directory not accessible: $PHOTO_PATH"
    echo "  Photo list will be generated when directory becomes available"
fi

# ==============================================================================
# STEP 12: Enable and start web admin service
# ==============================================================================
echo
echo "========================================================"
echo "STEP 12/12: Configuring Web Admin Service"
echo "========================================================"

sudo systemctl enable screensaver-web.service 2>/dev/null && {
    echo "✓ Web admin service enabled (will start on boot)"
} || {
    echo "⚠ Failed to enable web admin service"
}

sudo systemctl start screensaver-web.service 2>/dev/null && {
    echo "✓ Web admin service started"
    WEB_PORT=$(grep "web_admin_port:" "$CONFIG_FILE" | awk '{print $2}')
    WEB_PORT=${WEB_PORT:-5000}
    echo "  Access at: http://$(hostname -I | awk '{print $1}'):$WEB_PORT"
} || {
    echo "⚠ Failed to start web admin service (check logs with: sudo journalctl -u screensaver-web)"
}

# ==============================================================================
# Installation Complete
# ==============================================================================
echo
echo "========================================================"
echo "   Installation Complete!"
echo "========================================================"
echo
echo "Your system has been configured as a kiosk screensaver."
echo
echo "CONFIGURATION SUMMARY:"
echo "  - Boot mode: CLI with auto-login"
echo "  - Dashboard URL: $DASHBOARD_URL"
if [ "$HA_ENABLED" = "true" ]; then
echo "  - Home Assistant: $HA_URL"
fi
echo "  - Photo path: $PHOTO_PATH"
echo "  - Install directory: $INSTALL_DIR"
echo
WEB_PORT=$(grep "web_admin_port:" "$CONFIG_FILE" | awk '{print $2}')
WEB_PORT=${WEB_PORT:-5000}
PI_IP=$(hostname -I | awk '{print $1}')
echo "WEB ADMIN PANEL:"
echo "  http://$PI_IP:$WEB_PORT"
echo "  (Bookmark this URL for easy access to screensaver settings)"
echo
echo "NEXT STEPS:"
echo
if [ "$NEED_LOGOUT" = true ]; then
echo "1. IMPORTANT: Logout and login again for group permissions to take effect"
echo "   (input and i2c groups required for screensaver operation)"
echo
fi
echo "2. Reboot your system to activate CLI boot mode and start the kiosk"
echo "   sudo reboot"
echo
echo "3. After reboot, the system will:"
echo "   - Start in CLI mode with auto-login"
echo "   - Launch labwc Wayland compositor"
echo "   - Open Home Assistant dashboard in Chromium kiosk mode"
echo "   - Start the screensaver system in the background"
echo
echo "4. Configure Home Assistant integration (if enabled):"
echo "   - Create input_boolean.disable_screensaver in Home Assistant"
echo "   - Get long-lived access token from HA profile"
echo "   - Save token to ~/.ha_token"
echo
echo "5. Access web admin panel:"
WEB_PORT=$(grep "web_admin_port:" "$CONFIG_FILE" | awk '{print $2}')
WEB_PORT=${WEB_PORT:-5000}
echo "   http://$(hostname -I | awk '{print $1}'):$WEB_PORT"
echo "   Use it to:"
echo "   - Adjust timing settings (idle timeout, day/night mode times)"
echo "   - Configure photo slideshow interval"
echo "   - Set up scheduled reboots"
echo "   - Test Home Assistant connection"
echo "   - Manually trigger photo list regeneration"
echo
echo "6. DDC/CI Monitor Control (optional):"
echo "   - Most modern monitors support DDC/CI for brightness control"
echo "   - Test with: ddcutil detect"
echo "   - If your monitor is not detected, screensaver will still work"
echo "     but brightness control will be skipped"
echo
echo "MANUAL CONFIGURATION:"
echo "  - Edit config: nano $CONFIG_FILE"
echo "  - View logs: journalctl -u screensaver-web -f"
echo "  - Restart services: sudo systemctl restart screensaver-web"
echo
echo "========================================================"
echo
