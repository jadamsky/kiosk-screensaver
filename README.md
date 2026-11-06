# Kiosk Screensaver System

> **Author's Note:** This project was created to solve a very specific need - a fast-responding slideshow screensaver for a Raspberry Pi 5 running a Home Assistant dashboard in kiosk mode, every other option I found for a slideshow screensaver would be very slow to close and get back to the dashboard, this closed quickly, I also thried ot ensure that there was no memory leaks so it can run for days without haveing any memory issue or CPU issues. I developed this system using Visual Studio Code with significant assistance from the Claude Code extension. My personal coding ability is quite limited, and this project wouldn't have been possible without AI assistance. I'm sharing it publicly in case others have similar needs, but please be aware of its origins when using or contributing.

A comprehensive, configurable screensaver system for Raspberry Pi 5 kiosk displays with Home Assistant integration.

Perfect for creating a wall-mounted Home Assistant dashboard that automatically shows a photo slideshow when idle.

**Optimized for Raspberry Pi 5** with automatic Chromium version management and memory leak prevention for long-term stability.

## Features

- **Automatic Idle Detection**: Monitors keyboard, mouse, and touchscreen input
- **Time-Based Modes**: Photo slideshow during day hours, blank screen + monitor off at night
- **Per-Day Night Mode Scheduling**: Different night mode start times for each day of the week
- **Home Assistant Integration**: Remote enable/disable via HA entity (optional)
- **Web Admin Panel**: Browser-based configuration interface (port 5000)
- **Display Power Management**: DDC/CI brightness control, monitor power on/off
- **WiFi Stability**: Automatic WiFi power save disable to prevent network dropouts
- **WiFi Watchdog**: Automatically reconnects if WiFi fails to come back after a reboot or drops out
- **Persistent Logging**: System logs survive reboots, so failures can be diagnosed afterwards
- **Auto Photo List Generation**: Scheduled regeneration of photo catalog
- **Privacy Mode**: Optional blank screen instead of photos
- **Scheduled Reboots**: Automatic system maintenance reboots
- **Movie Mode**: Quick script to force dark mode for watching movies
- **Memory Leak Prevention**: Process management prevents Chromium memory accumulation over extended runtime
- **HTTP Server Auto-Recovery**: Automatic restart of photo serving if servers stop

## System Requirements

### Hardware
- **Raspberry Pi 5** (8GB RAM recommended, 4GB works)
- **Monitor**: DDC/CI-compliant monitor recommended for brightness control (most modern monitors support this)
- **Storage**: 32GB+ microSD card
- **Input**: Touchscreen, mouse, or keyboard for interaction

### Software
- **Fresh Raspberry Pi OS (64-bit)** - Debian Trixie or newer
- **Desktop mode with auto-login** initially configured (installer will switch to CLI)
- Internet connection for downloading dependencies

## Installation

### 1. Prepare Your Raspberry Pi

1. Flash fresh **Raspberry Pi OS (64-bit)** to microSD card using Raspberry Pi Imager
2. During setup, configure:
   - Username and password
   - WiFi network
   - Enable SSH (optional, but recommended)
3. Boot into Desktop mode and complete initial setup
4. Configure auto-login in Desktop mode (System Settings → Users)

### 2. Transfer Files

Transfer this entire folder to your Raspberry Pi:

**Option A: Using WinSCP or similar (from Windows)**
```
Source: This folder
Destination: /home/[your-username]/kiosk-screensaver
```

**Option B: Using git (if available)**
```bash
cd ~
git clone [your-repo-url] kiosk-screensaver
```

**Option C: Using scp (from Linux/Mac)**
```bash
scp -r kiosk-screensaver pi@[pi-ip-address]:~/
```

### 3. Fix Line Endings (if transferring from Windows)

```bash
cd ~/kiosk-screensaver
find . -name "*.sh" -exec sed -i 's/\r$//' {} \;
```

### 4. Run Installer

```bash
cd ~/kiosk-screensaver
bash install.sh
```

The installer will:
1. Install all required dependencies (labwc, chromium, ddcutil, iw, etc.)
2. Ask for your configuration:
   - Home Assistant URL (optional)
   - Dashboard URL (required)
   - Photos folder path
3. Switch boot mode from Desktop to CLI
4. Configure auto-start for labwc, Chromium, and screensaver
5. Set up web admin panel
6. **Disable WiFi power save** to prevent network dropouts
7. **Install the WiFi watchdog** and enable persistent system logging
8. Generate initial photo list
9. Configure permissions and systemd services

### 5. Reboot

```bash
sudo reboot
```

After reboot:
- System starts in CLI mode (you'll see text briefly)
- labwc Wayland compositor starts automatically
- Chromium opens your dashboard in kiosk mode
- Screensaver runs in the background

## Configuration

### Web Admin Panel

Access at `http://[pi-ip-address]:5000`

Configure:
- Idle timeout (seconds before screensaver activates)
- Slideshow interval (seconds between photos)
- Day/night mode times
- Scheduled reboots
- Photo list regeneration

### Home Assistant Integration (Optional)

If enabled during install:

**IMPORTANT:** Use your Home Assistant's **local network IP address** (e.g., `https://192.168.1.100:8123`), NOT your DuckDNS or external URL. The screensaver runs on the same local network as Home Assistant and should communicate locally for best performance and reliability.

1. Create an `input_boolean` in Home Assistant:
   ```yaml
   input_boolean:
     disable_screensaver:
       name: Disable Screensaver
       icon: mdi:monitor-off
   ```

2. Get a Long-Lived Access Token:
   - In HA, go to your Profile → Security → Long-Lived Access Tokens
   - Create new token
   - Copy the token

3. Save token on Pi:
   ```bash
   echo "your-token-here" > ~/.ha_token
   ```

4. Test connection in web admin panel

**How it works:**
- When `input_boolean.disable_screensaver` is **OFF**: Screensaver works normally
- When **ON**: Screensaver is disabled (dashboard always visible)

### Photo Source

Configure your photo source path during installation or edit later in `config.yaml`.

**Important:** If using network shares or external drives, you are responsible for mounting them properly on your Raspberry Pi. The examples below show the basic commands, but configuring persistent mounts, credentials, and network stability is outside the scope of this project. Refer to Raspberry Pi and Linux documentation for mounting network shares.

**Local photos:**
```bash
photo_source_path: /home/username/Pictures
```

**Network share (Windows/Samba) - Example:**
```bash
# First, mount the share (add to /etc/fstab for auto-mount on boot)
sudo mkdir /mnt/photos
sudo mount -t cifs //192.168.1.100/Pictures /mnt/photos -o username=user,password=pass

# Then configure:
photo_source_path: /mnt/photos
```

**NFS share - Example:**
```bash
sudo mkdir /mnt/photos
sudo mount -t nfs 192.168.1.100:/photos /mnt/photos

photo_source_path: /mnt/photos
```

**Note:** Network share mounting configuration, credentials management, and ensuring mounts persist across reboots are the user's responsibility. Search for "Raspberry Pi mount network share" or "Linux fstab configuration" for detailed guides.

## Usage

### Normal Operation

- **Boot**: After system startup, screensaver waits 90 seconds before it can activate (boot grace period)
  - This ensures the Wayland compositor is fully initialized
  - Prevents display issues on fresh boot
- **Idle**: After configured timeout (default 20 seconds), slideshow starts
- **Wake**: Tap screen or move mouse to return to dashboard
- **Day mode** (6:15 AM - 11:00 PM): Photo slideshow
- **Night mode** (11:00 PM - 6:15 AM): Blank screen + monitor off

### Movie Mode

Quick script to force dark screen while watching movies.

**Requirements:**
- SSH access to the Raspberry Pi
- Terminal session (or SSH client like PuTTY)

**Note:** This feature requires a persistent SSH connection. You'll need to set up SSH access to your Pi and keep a terminal session open. Configuration of SSH is outside the scope of this installation - refer to Raspberry Pi documentation for SSH setup.

**Usage:**
```bash
# SSH into your Pi, then run:
bash ~/kiosk-screensaver/force-night-screensaver.sh
```

**What it does:**
- Immediately activates night mode (blank screen, monitor off)
- Waits for input (tap screen or press any key)
- Exits and returns to normal operation
- Perfect for watching movies without the slideshow activating

**Automation Alternative:**
Instead of using this script, you can use the Home Assistant integration to disable the screensaver remotely via an HA automation or dashboard button.

## Known Limitations

### Raspberry Pi 5 Hardware Video Decode

The Raspberry Pi 5 has **limited hardware video decode** capabilities:

- **H.265/HEVC**: Hardware decode available via `/dev/video19` (rpi-hevc-dec)
- **H.264**: **NO hardware decode** - uses software decoding only
- **VP9/VP8**: Software decode only

**Impact on Dashboard Performance:**
- If your Home Assistant cameras stream H.264 (most common), expect ~15-20% CPU usage per video stream for software decode
- This is normal and expected behavior on Raspberry Pi 5
- To reduce CPU usage, consider:
  - Converting camera streams to H.265/HEVC (requires camera support)
  - Reducing video resolution or frame rate in Home Assistant
  - Limiting the number of simultaneous video streams on dashboard

**WebGL Rendering:**
- WebGL content (like Windy weather radar) uses SwiftShader software rendering
- Can use 50-95% GPU process CPU depending on complexity
- No hardware WebGL acceleration available on Pi 5

### Chromium Version Stability

This system is optimized for **Chromium 142.0.7444.175**:
- The installer automatically downgrades to this version
- Chromium 143+ has known stability issues on Raspberry Pi 5
- The installer prevents auto-updates using `apt-mark hold`
- Do not manually upgrade Chromium unless testing

## Troubleshooting

### System Health Check

A comprehensive health check script is included to diagnose issues:

```bash
cd ~/kiosk-screensaver
bash health-check.sh
```

This displays:
- Current screensaver mode and uptime
- Chromium process counts and memory usage
- System load and temperature
- Service status
- Hardware acceleration status
- Photo count

Use this as your first diagnostic step when troubleshooting issues.

### Screensaver not activating

```bash
# Check if screensaver process is running
pgrep -f screensaver.main

# View logs
journalctl -u screensaver-web -f

# Check input device permissions
ls -la /dev/input/event*

# Ensure you're in input group
groups | grep input
```

### Monitor brightness not working

```bash
# Test DDC/CI detection
ddcutil detect

# If not detected, your monitor may not support DDC/CI
# Screensaver will still work, just without brightness control
```

### Dashboard not loading

```bash
# Check if Chromium is running
pgrep chromium

# Check autostart file
cat ~/.config/labwc/autostart

# Restart labwc
pkill labwc
```

### High CPU usage on dashboard

**Normal behavior:**
- Dashboard with H.264 camera streams: 15-25% CPU per stream (software decode)
- WebGL content (weather radar, maps): 50-95% GPU process CPU
- Idle dashboard: 5-15% CPU

**If CPU is higher than expected:**
```bash
# Check which Chromium processes are using CPU
top -p $(pgrep chromium | tr '\n' ',' | sed 's/,$//')

# Verify Chromium version (should be 142.0.7444.175)
chromium --version

# Check for multiple Chromium instances
pgrep -a chromium | wc -l

# Verify VAAPI hardware decode is active
grep -i vaapi /proc/$(pgrep chromium | head -1)/environ
```

### System becoming unresponsive over time

This was a known issue caused by multiple Chromium instances accumulating. Fixed in current version:

```bash
# Verify you have the latest modes.py with process cleanup
grep -A 5 "Kill existing slideshow" ~/kiosk-screensaver/screensaver/modes.py

# Check for process accumulation
pgrep -a chromium | grep -E 'slideshow|screensaver'

# If you see old processes, update to latest version
```

### Dashboard appears but is non-functional after wake

**Symptoms:**
- Tap screen to wake from screensaver
- Dashboard UI appears but camera streams are dead
- Weather/external content doesn't load
- Buttons don't work or show "couldn't send event"
- Second wake attempt works fine

**This was caused by WiFi power save mode and has been fixed in the installer.**

**To verify the fix is applied:**
```bash
# Check WiFi power save status (should show "off")
sudo iw dev wlan0 get power_save

# Check if service is enabled
systemctl status disable-wifi-powersave.service

# If not applied, run the fix script
bash ~/kiosk-screensaver/scripts/disable-wifi-powersave.sh
```

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed analysis of this issue.

### Kiosk doesn't reconnect to WiFi after a reboot

**Symptoms:**
- After a reboot the display comes up, but the kiosk is unreachable on the network
- `nmcli device` shows `wlan0` as `disconnected` and it never reconnects on its own
- Running `sudo nmcli connection up <your-wifi-name>` by hand fixes it immediately

**Cause:** If the access point briefly rejects the kiosk or times out the
WPA handshake while it is connecting (for example while the router is busy),
NetworkManager can treat the failure as a wrong password. With no one there
to enter a new one, it marks the connection as failed (`no-secrets`) and
stops auto-connecting until someone reconnects manually.

**Fix:** The installer sets up `wifi-watchdog.service`, which checks every
30 seconds that `wlan0` has an address and can reach its gateway, and
reconnects if not. To install it on an existing system:
```bash
bash ~/kiosk-screensaver/scripts/install-wifi-watchdog.sh
```

```bash
# Check the watchdog is running
systemctl status wifi-watchdog

# See what it has done (failures and recoveries only - quiet when healthy)
journalctl -u wifi-watchdog

# One-shot link check
sudo python3 /usr/local/bin/wifi-watchdog.py --check
```

### Logs disappear after a reboot

Raspberry Pi OS keeps system logs in memory only by default, so a reboot or
power cut erases the evidence of whatever went wrong. The installer enables
persistent logging (capped at 200MB). To enable it on an existing system:
```bash
bash ~/kiosk-screensaver/scripts/enable-persistent-journal.sh

# After a reboot, view the previous boot's logs
journalctl --list-boots
journalctl -b -1
```

Note: setting `Storage=persistent` in `/etc/systemd/journald.conf` alone has
no effect on Raspberry Pi OS, because a drop-in shipped with the OS
(`/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf`) overrides
it. The script adds its own drop-in that takes precedence.

### Web admin not accessible

```bash
# Check if service is running
sudo systemctl status screensaver-web

# Restart service
sudo systemctl restart screensaver-web

# Check logs
sudo journalctl -u screensaver-web -f
```

## Advanced Configuration

### Manual Configuration File

Edit `~/kiosk-screensaver/config.yaml` for advanced settings:

```bash
nano ~/kiosk-screensaver/config.yaml
```

After editing, restart services:
```bash
sudo systemctl restart screensaver-web
pkill -f screensaver.main  # Will auto-restart from autostart
```

### Boot Grace Period

The `boot_grace_period` setting (default: 90 seconds) prevents the screensaver from activating immediately after system boot. This is critical for proper operation:

- Wayland compositor (labwc) needs time to fully initialize after boot
- Without this delay, the screensaver may launch Chromium windows before the compositor is ready
- This can cause display issues like half-screen rendering
- **Recommended minimum: 60 seconds** for Raspberry Pi 5
- Do not disable this setting (set to 0) unless you're using systemd service startup with proper dependencies

### Scheduled Reboots

Configure in web admin panel or config.yaml:
```yaml
features:
  scheduled_reboot:
    enabled: true
    frequency: "weekly"  # or "daily"
    day_of_week: 1  # 0=Monday, 6=Sunday
    reboot_time: "0300"  # 3:00 AM
```

### Per-Day Night Mode Scheduling

Configure different night mode start times for each day of the week:

```yaml
timing:
  day_mode_start_time: '0615'  # 6:15 AM every day
  night_mode_start_time:       # Different times per day
    monday: '2200'    # 10:00 PM
    tuesday: '2200'
    wednesday: '2200'
    thursday: '2200'
    friday: '2350'    # 11:50 PM (stay up later on weekends)
    saturday: '2350'
    sunday: '2200'
```

Or use a single time for all days (old format still supported):
```yaml
timing:
  night_mode_start_time: '2200'  # 10:00 PM every day
```

### Privacy Mode

Disable photo slideshow, use blank screen instead:
```yaml
features:
  privacy_mode: true
```

## Architecture

### Components

1. **Python Screensaver Manager** (`screensaver/manager.py`)
   - Monitors input devices using inotify
   - Handles idle timeout and mode switching
   - Integrates with Home Assistant

2. **Web Admin Panel** (`screensaver/web/`)
   - Flask-based web interface
   - Real-time configuration updates
   - System status monitoring

3. **Photo Manager** (`screensaver/photos.py`)
   - Generates photo list from source directory
   - Scheduled auto-regeneration
   - Excludes large files, caches metadata

4. **Mode Handler** (`screensaver/modes.py`)
   - Day mode: Launches Chromium with slideshow
   - Night mode: Blank screen + monitor power off
   - Handles mode transitions
   - **Process cleanup**: Kills old slideshow/night instances before launching new ones
   - **Cache clearing**: Removes Chromium cache on each launch to prevent memory buildup

### File Structure

```
~/kiosk-screensaver/
├── install.sh              # Installation script
├── uninstall.sh            # Uninstallation script
├── health-check.sh         # System health diagnostic
├── config.yaml             # Main configuration (generated by installer)
├── config.yaml.template    # Template used by installer
├── requirements.txt        # Python dependencies
├── TROUBLESHOOTING.md      # Detailed troubleshooting guide
├── screensaver/            # Python package
│   ├── main.py            # Entry point
│   ├── manager.py         # Core screensaver logic
│   ├── modes.py           # Day/night mode handling
│   ├── servers.py         # HTTP server management
│   ├── photo_manager.py   # Photo list generation
│   ├── config.py          # Configuration loader
│   ├── ha_integration.py  # Home Assistant integration
│   └── web/               # Web admin panel
├── static/                 # HTML/JS for slideshow
├── scripts/                # Utility scripts
│   ├── disable-wifi-powersave.sh    # WiFi stability fix
│   ├── wifi-watchdog.py             # WiFi auto-reconnect watchdog
│   ├── install-wifi-watchdog.sh     # Installs the watchdog service
│   ├── enable-persistent-journal.sh # Keeps system logs across reboots
│   └── diagnose-offline.sh          # Network diagnostic tool
└── force-night-screensaver.sh     # Movie mode script

Note: Systemd service files (/etc/systemd/system/disable-wifi-powersave.service,
wifi-watchdog.service, screensaver-web.service) and sudoers configuration are
generated automatically by the installer with your specific user and paths.
```

## Credits

Built for Raspberry Pi 5 kiosk installations with Home Assistant integration.

Developed with significant assistance from Claude Code (Anthropic).

## License

MIT License - See LICENSE file for details.

Free to use, modify, and distribute. No warranty provided.

## Support

For issues and questions:
1. Check the [Troubleshooting](#troubleshooting) section above
2. Review [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed diagnostics
3. Run `health-check.sh` to gather system information
4. Open an issue on GitHub with health check output and logs

## Contributing

Contributions welcome! This project was built with AI assistance and could benefit from community improvements.

Areas that could use work:
- Ethernet support testing (currently optimized for WiFi)
- Alternative compositor support (currently requires labwc)
- Additional photo source integrations
- Performance optimizations
- Documentation improvements
