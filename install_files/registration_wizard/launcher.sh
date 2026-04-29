#!/usr/bin/env bash
# SchoolAir Gatekeeper – boot launcher
#
# Called by schoolair-launcher.service on every boot.
# Logic:
#   1. Wait up to 60 s for a client (non-AP) Wi-Fi connection.
#   2. If a client connection is found → device can reach the internet; exit.
#   3. Otherwise → bring up the AP hotspot and start the registration wizard.
#      The wizard handles registered vs unregistered state (wifi-only or full form).

set -euo pipefail

WIZARD_SERVICE="schoolair-wizard"
AP_CONN="SchoolAir_AP"
POLL_INTERVAL=5   # seconds between connectivity checks
MAX_WAIT=60       # total seconds to wait for a client connection

log() { echo "[schoolair-launcher] $*"; }

# ── 1. Wait for a known client Wi-Fi connection ────────────────────────────────
# We specifically exclude the SchoolAir_AP hotspot connection — it would have
# an IP too, but that is not a real upstream network.
log "No status.json found. Waiting up to ${MAX_WAIT}s for a client Wi-Fi network…"

elapsed=0
connected=false

while [ "$elapsed" -lt "$MAX_WAIT" ]; do
    # List active, activated Wi-Fi connections that are NOT the AP hotspot.
    active_sta=$(nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null \
        | awk -F: '$2=="802-11-wireless" && $3=="activated" && $1!="'"$AP_CONN"'" {print $1; exit}')

    if [ -n "$active_sta" ]; then
        log "Connected to client network '${active_sta}'. No wizard needed. Exiting."
        connected=true
        break
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
done

if "$connected"; then
    exit 0
fi

# ── 3. No client network — start the AP and wizard ────────────────────────────
log "No client network after ${MAX_WAIT}s. Starting AP hotspot…"

if nmcli con up "$AP_CONN" 2>/dev/null; then
    log "AP '${AP_CONN}' is up."
else
    log "WARNING: Could not bring up NM connection '${AP_CONN}'."
    log "         Falling back to hostapd (if installed)…"
    systemctl start hostapd 2>/dev/null || log "WARNING: hostapd also unavailable."
fi

# Give the AP a moment to initialise before the wizard opens port 80.
sleep 3

log "Starting ${WIZARD_SERVICE}…"
systemctl start "$WIZARD_SERVICE"
