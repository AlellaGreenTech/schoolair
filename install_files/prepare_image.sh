#!/usr/bin/env bash
# SchoolAir Golden Image Preparation Script
#
# Run as the admin user before shutting down to image the SD card.
# Removes all device-unique state so every clone boots fresh.
#
#   curl -sSL https://raw.githubusercontent.com/AlellaGreenTech/schoolair/main/install_files/prepare_image.sh | sudo bash
#
# Usage:  bash prepare_image.sh
#         sudo shutdown -h now   ← after it completes

set -euo pipefail

ADMIN_USER="${SUDO_USER:-admin}"
ADMIN_HOME="/home/${ADMIN_USER}"

BOLD='\033[1m'; GREEN='\033[0;32m'; NC='\033[0m'
step() { echo; echo -e "${BOLD}▶ $*${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }

echo -e "${BOLD}━━━ SchoolAir Golden Image Preparation ━━━${NC}"
echo    "    User: ${ADMIN_USER}  |  Home: ${ADMIN_HOME}"

# ── 1. Stop services ──────────────────────────────────────────────────────────
step "Stopping services"
for svc in schoolair-wizard schoolair-launcher nodered sen6x nginx; do
    sudo systemctl stop "$svc" 2>/dev/null && ok "Stopped $svc" || true
done

# ── 2. Device identity & registration state ───────────────────────────────────
step "Removing device identity"
rm -f "${ADMIN_HOME}/.device_token"
rm -f "${ADMIN_HOME}/.config/schoolair/status.json"
rm -f "${ADMIN_HOME}/.config/schoolair/staging.json"
rm -f "${ADMIN_HOME}/.config/schoolair/last_error.txt"
ok "Device token and wizard state cleared"

# ── 3. nginx: ensure disabled so wizard owns port 80 on first boot ────────────
step "Resetting nginx to disabled"
sudo systemctl disable nginx 2>/dev/null || true
ok "nginx disabled"

# ── 4. Node-RED cleanup ───────────────────────────────────────────────────────
step "Cleaning Node-RED"
rm -f  "${ADMIN_HOME}/.node-red/.config.json.backup"
rm -f  "${ADMIN_HOME}/.node-red/flows_"*.json.backup 2>/dev/null || true
rm -rf "${ADMIN_HOME}/.node-red/context/"
ok "Node-RED backups and runtime context cleared"

# ── 6. APT cache ──────────────────────────────────────────────────────────────
step "Cleaning APT cache"
sudo apt-get autoremove -y -qq
sudo apt-get clean
ok "APT cache cleared"

# ── 7. Reset cloud-init ───────────────────────────────────────────────────────
step "Resetting cloud-init"
sudo cloud-init clean --logs
sudo rm -rf /var/lib/cloud/instances/*
# Pi Imager writes WiFi credentials to /boot/firmware/network-config.
# cloud-init clean causes cloud-init to re-run on next boot, which would
# re-create the home WiFi NM profile from that file. Strip the wifi section
# so clones don't inherit the original owner's home network credentials.
if [ -f /boot/firmware/network-config ]; then
    sudo python3 - <<'EOF'
import re, pathlib
p = pathlib.Path("/boot/firmware/network-config")
txt = p.read_text()
# Remove everything from the 'wifis:' key to the end of the file (or next top-level key).
txt = re.sub(r'\nwifis:.*', '', txt, flags=re.DOTALL)
p.write_text(txt.rstrip() + '\n')
EOF
    ok "cloud-init network-config: WiFi section removed"
fi
ok "cloud-init reset"

# ── 8. Reset hostname ─────────────────────────────────────────────────────────
step "Ensuring first-boot service is enabled for clones"
sudo systemctl enable schoolair-first-boot.service 2>/dev/null \
    && ok "schoolair-first-boot.service enabled" \
    || ok "schoolair-first-boot.service not found (old image — install schoolair_setup.sh first)"

step "Resetting hostname"
sudo bash "${ADMIN_HOME}/set_hostname.sh" "schoolair-template" > /dev/null
ok "Hostname → schoolair-template  (Pi Imager can override per-device when flashing)"

# ── 9. SSH host keys ──────────────────────────────────────────────────────────
step "Removing SSH host keys"
sudo rm -f /etc/ssh/ssh_host_*
# The regenerate_ssh_host_keys service disables itself after its first run.
# Re-enable it so the next boot (of a clone) regenerates fresh keys.
sudo systemctl enable regenerate_ssh_host_keys.service 2>/dev/null || true
ok "Keys removed — regenerate_ssh_host_keys.service re-enabled for next boot"

# ── 10. Logs and shell history ────────────────────────────────────────────────
step "Wiping logs and shell history"
sudo find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
sudo truncate -s 0 /var/log/schoolair-setup.log 2>/dev/null || true
cat /dev/null > "${ADMIN_HOME}/.bash_history"
history -c 2>/dev/null || true
ok "Logs and history cleared"

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}${BOLD}Ready to image.${NC}"
echo
echo "  1. Shut down the Pi:"
echo "       sudo shutdown -h now"
echo
echo "  2. Attach the SD card to your laptop, then find its device:"
echo "       lsblk   (look for ~16/32 GB — confirm before proceeding)"
echo
echo "  3. Create the image:"
echo "       sudo dd if=/dev/sdX of=schoolair-golden-$(date +%Y%m%d).img bs=4M status=progress"
echo "       gzip -9 schoolair-golden-$(date +%Y%m%d).img"
echo
echo "  4. Flash a clone with Raspberry Pi Imager → 'Use custom image'"
echo "     In Imager's advanced settings (⚙) set a unique hostname per device."
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ── Last step: drop WiFi client connections ───────────────────────────────────
# Done last so SSH stays alive for the entire script. Losing the connection
# here is the signal that everything completed — safe to power off.
echo
step "Removing saved WiFi connections (preserving SchoolAir_AP)"
echo "  (SSH will disconnect now if you are connected via the home network)"
nmcli -t -f NAME,TYPE connection show \
    | awk -F: '$2=="802-11-wireless" && $1!="SchoolAir_AP" {print $1}' \
    | while IFS= read -r CON; do
        sudo nmcli connection delete "$CON" 2>/dev/null \
            && ok "Deleted WiFi profile: $CON" || true
    done
