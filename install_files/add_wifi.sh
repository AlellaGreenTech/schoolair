#!/usr/bin/env bash
# SchoolAir – Pre-store a WiFi profile in NetworkManager
#
# Usage:
#   add_wifi.sh <SSID> <password> wpa-psk   # WPA / WPA2 personal
#   add_wifi.sh <SSID> ""         open      # no password

set -euo pipefail

IFACE="wlan0"
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}   $*"; }
die()  {
    echo -e "\n${RED}${BOLD}Error:${NC} $*" >&2
    echo >&2
    echo -e "Usage:  $(basename "$0") <SSID> <password> <type>" >&2
    echo >&2
    echo -e "Types:" >&2
    echo -e "  ${BOLD}wpa-psk${NC}   WPA / WPA2 personal  (most common)" >&2
    echo -e "  ${BOLD}open${NC}      No password — pass \"\" as the password argument" >&2
    echo >&2
    echo -e "Note: Pi Zero W does not support WPA3." >&2
    exit 1
}

SSID="${1:-}"
PASSWORD="${2:-}"
SECURITY="${3:-}"

[ -n "$SSID" ]     || die "SSID is required."
[ -n "$SECURITY" ] || die "Security type is required."

case "$SECURITY" in
    wpa-psk)
        [ -n "$PASSWORD" ] || die "A password is required for wpa-psk."
        ;;
    open)
        ;;
    *)
        die "Unknown type '${SECURITY}'."
        ;;
esac

echo -e "${BOLD}Adding WiFi profile: '${SSID}' (${SECURITY})${NC}"

# Replace any existing profile with the same name
if nmcli con show "$SSID" &>/dev/null; then
    warn "Profile '${SSID}' already exists — replacing it"
    sudo nmcli con delete "$SSID" >/dev/null
fi

case "$SECURITY" in
    wpa-psk)
        sudo nmcli connection add \
            type wifi                     \
            con-name "$SSID"              \
            ifname   "$IFACE"             \
            ssid     "$SSID"              \
            --                            \
            wifi-sec.key-mgmt wpa-psk     \
            wifi-sec.psk      "$PASSWORD" \
            >/dev/null
        ;;
    open)
        sudo nmcli connection add \
            type wifi        \
            con-name "$SSID" \
            ifname   "$IFACE"\
            ssid     "$SSID" \
            >/dev/null
        ;;
esac

ok "Profile '${SSID}' stored — auto-connects on next boot when in range"
