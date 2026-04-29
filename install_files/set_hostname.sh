#!/usr/bin/env bash
# SchoolAir Hostname Utility
#
# Usage:
#   sudo bash set_hostname.sh               # generate schoolair-YYMDD-XXXX and apply
#   sudo bash set_hostname.sh <hostname>    # apply an exact hostname (e.g. schoolair-template)
#
# Prints the resulting hostname to stdout.
# Updates all four locations that cloud-init / systemd-hostnamed read.

set -euo pipefail

_apply_hostname() {
    local hn="$1"
    # 1. cloud-init seed file (Pi Imager writes this)
    if [ -f /boot/firmware/user-data ] && grep -q "^hostname:" /boot/firmware/user-data; then
        sed -i "s/^hostname:.*/hostname: ${hn}/" /boot/firmware/user-data
    fi
    # 2. cloud-init previous-hostname cache (prevents cc_update_hostname from reverting)
    mkdir -p /var/lib/cloud/data
    echo "$hn" > /var/lib/cloud/data/previous-hostname
    # 3. /etc/hostname (read by systemd-hostnamed at boot)
    echo "$hn" > /etc/hostname
    # 4. /etc/hosts loopback entry
    if grep -q "127\.0\.1\.1" /etc/hosts; then
        sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${hn}/" /etc/hosts
    else
        printf '127.0.1.1\t%s\n' "$hn" >> /etc/hosts
    fi
    # 5. Wipe cloud-init instance cache so it re-reads user-data on the next boot
    cloud-init clean 2>/dev/null || true
    # 6. Live UTS hostname for the current session
    hostname "$hn"
    echo "$hn"
}

if [ -n "${1:-}" ]; then
    _apply_hostname "$1"
else
    # Generate schoolair-YYMDD-XXXX:
    #   YY   = 2-digit year
    #   M    = hex month: 1-9 for Jan–Sep, A-C for Oct–Dec
    #   DD   = 2-digit day
    #   XXXX = lower 16 bits of seconds-since-midnight (time-of-day uniquifier)
    _month_hex=$(printf '%X' "$(date +%-m)")
    _midnight=$(date -d "$(date +%Y-%m-%d) 00:00:00" +%s)
    _secs=$(( $(date +%s) - _midnight ))
    _hn="schoolair-$(date +%y)${_month_hex}$(date +%d)-$(printf '%04x' $(( _secs % 65536 )))"
    _apply_hostname "$_hn"
fi
