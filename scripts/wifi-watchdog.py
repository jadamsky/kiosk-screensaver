#!/usr/bin/env python3
"""Wi-Fi watchdog: every INTERVAL seconds, make sure wlan0 has an address and
can reach its gateway. If not, ask NetworkManager to reconnect, escalating if
that keeps failing. Runs as wifi-watchdog.service.

Why this exists: if the access point briefly refuses or times out a
connection (e.g. while it is busy or restarting), NetworkManager can mistake
the failed WPA handshake for a wrong password. On a headless kiosk there is
nobody to type a new one, so the connection fails with reason 'no-secrets'
and NetworkManager stops auto-connecting it until someone runs
`nmcli connection up` by hand. This watchdog does that automatically.

Only the local link is checked (not the internet), so an ISP outage doesn't
cause pointless reconnect churn. Logs only failures and recovery, so it is
quiet when healthy. Logs go to the journal: journalctl -u wifi-watchdog

  wifi-watchdog.py --check    one-shot status: prints OK or DOWN: <reason>

Set WIFI_WATCHDOG_CONNECTION (name or UUID) in the service environment to
pin which NetworkManager profile to bring up; by default the most recently
used Wi-Fi profile with autoconnect enabled is used.
"""
import os
import re
import subprocess
import sys
import time

IFACE = "wlan0"
INTERVAL = 30               # seconds between checks
FORCE_REASSOC_AFTER = 2     # consecutive failures before a full disconnect + reconnect
RESTART_NM_AFTER = 4        # consecutive failures before restarting NetworkManager (~2 min)
RESTART_NM_EVERY = 10       # ...then again every N failures (~5 min)
CONNECT_WAIT = 45           # seconds nmcli waits for activation (AP rejects + backoff took ~20s)


def log(msg):
    print(msg, flush=True)


def run(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except OSError as e:
        return 127, str(e)


def clean(text):
    """Flatten nmcli output (it can contain \\r and escape codes) to one plain line."""
    return " ".join(re.sub(r"[\x00-\x1f\x7f]", " ", text).split())


def device_state():
    """Return NetworkManager's state for IFACE as (code, text), e.g. (100, 'connected')."""
    rc, out = run(["nmcli", "-g", "GENERAL.STATE", "device", "show", IFACE], 10)
    m = re.match(r"(\d+)\s*\((.*)\)", clean(out))
    if rc != 0 or not m:
        return 0, "unknown"
    return int(m.group(1)), m.group(2)


def link_ok():
    """Return (ok, reason). ok means: has an IPv4 address and the gateway answers."""
    rc, out = run(["ip", "-4", "-o", "addr", "show", "dev", IFACE, "scope", "global"], 10)
    if rc != 0 or not out:
        return False, f"no IPv4 address on {IFACE}"
    rc, out = run(["ip", "-4", "route", "show", "default", "dev", IFACE], 10)
    m = re.search(r"default via (\S+)", out)
    if not m:
        return False, f"no default route via {IFACE}"
    gateway = m.group(1)
    rc, _ = run(["ping", "-c", "2", "-W", "2", "-I", IFACE, gateway], 15)
    if rc != 0:
        return False, f"gateway {gateway} unreachable"
    return True, ""


def wifi_profile():
    """Return the NetworkManager profile (UUID or name) to activate on IFACE, or None."""
    pinned = os.environ.get("WIFI_WATCHDOG_CONNECTION", "").strip()
    if pinned:
        return pinned
    rc, out = run(["nmcli", "-t", "-f", "UUID,TYPE,AUTOCONNECT,TIMESTAMP", "connection", "show"], 10)
    if rc != 0:
        return None
    best, best_ts = None, -1
    for line in out.splitlines():
        parts = line.split(":")
        if len(parts) != 4:
            continue
        uuid, ctype, autoconnect, ts = parts
        if ctype != "802-11-wireless" or autoconnect != "yes":
            continue
        ts = int(ts) if ts.isdigit() else 0
        if ts > best_ts:
            best, best_ts = uuid, ts
    return best


def reconnect(failures):
    if failures >= RESTART_NM_AFTER and (failures - RESTART_NM_AFTER) % RESTART_NM_EVERY == 0:
        log("escalating: restarting NetworkManager")
        run(["systemctl", "restart", "NetworkManager"], 90)
        time.sleep(10)
    run(["nmcli", "radio", "wifi", "on"], 10)
    if failures >= FORCE_REASSOC_AFTER:
        # A link that is associated but dead still looks "connected" to nmcli,
        # so tear it down first to force a fresh association and DHCP lease.
        run(["nmcli", "device", "disconnect", IFACE], 20)
    run(["nmcli", "device", "wifi", "rescan", "ifname", IFACE], 15)  # best effort
    # Bring the profile up explicitly rather than with `nmcli device connect`:
    # an explicit activation clears NetworkManager's autoconnect block (set
    # after a 'no-secrets' failure), and doesn't depend on the AP being in
    # the latest scan results.
    profile = wifi_profile()
    if profile:
        cmd = ["nmcli", "--wait", str(CONNECT_WAIT), "connection", "up", profile, "ifname", IFACE]
    else:
        cmd = ["nmcli", "--wait", str(CONNECT_WAIT), "device", "connect", IFACE]
    rc, out = run(cmd, CONNECT_WAIT + 15)
    if failures <= 5 or failures % 10 == 0:
        log(f"reconnect attempt {failures}: {' '.join(cmd[3:])} -> rc={rc} {clean(out)}")


def main():
    if "--check" in sys.argv:
        ok, reason = link_ok()
        print("OK" if ok else f"DOWN: {reason}")
        sys.exit(0 if ok else 1)

    failures = 0
    down_since = 0.0
    log(f"wifi-watchdog started: checking {IFACE} every {INTERVAL}s")
    while True:
        started = time.monotonic()
        ok, reason = link_ok()
        if ok:
            if failures:
                down_for = int(time.monotonic() - down_since)
                log(f"{IFACE} recovered after {failures} failed check(s), ~{down_for}s down")
            failures = 0
        else:
            if failures == 0:
                down_since = started
            failures += 1
            code, state = device_state()
            if failures <= 5 or failures % 10 == 0:
                log(f"{IFACE} check failed ({failures}): {reason} [NM state: {code} {state}]")
            # NetworkManager is mid-activation (prepare..secondaries): give it one
            # interval to finish on its own instead of restarting it from scratch.
            if failures == 1 and 40 <= code < 100:
                log(f"NetworkManager is still activating {IFACE}; waiting one interval")
            else:
                reconnect(failures)
        time.sleep(max(1, INTERVAL - (time.monotonic() - started)))


if __name__ == "__main__":
    main()
