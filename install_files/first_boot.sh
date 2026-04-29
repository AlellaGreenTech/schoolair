#!/usr/bin/env bash
# SchoolAir First-Boot Hostname Assignment
#
# Runs on every boot via schoolair-first-boot.service.
# Acts only when the hostname is exactly "schoolair-template" (freshly flashed clone).

set -euo pipefail

[[ "$(hostname)" == "schoolair-template" ]] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[schoolair-first-boot] Template hostname detected — assigning unique hostname…"
NEW_HN=$(bash "${SCRIPT_DIR}/set_hostname.sh")
echo "[schoolair-first-boot] Hostname is now: ${NEW_HN}"
