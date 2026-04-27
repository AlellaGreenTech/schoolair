#!/usr/bin/env bash
# SchoolAir Gatekeeper – automated deployment script
#
# Usage:  sudo bash setup.sh
#
# What this does:
#   1. Installs system packages (python3-pip, avahi-daemon)
#   2. Installs Python dependencies (microdot)
#   3. Copies wizard files to /home/admin/registration_wizard/
#   4. Creates a NetworkManager Wi-Fi hotspot (SchoolAir_AP)
#   5. Drops a dnsmasq captive-portal config into NM's plugin dir
#   6. Configures Avahi for schoolair-register.local mDNS
#   7. Installs and enables the systemd launcher service
#   8. Verifies the installation
#
# Idempotent — safe to run more than once.
# Tested on Raspberry Pi OS Bullseye and Bookworm.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
INSTALL_DIR="/home/admin/registration_wizard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_IFACE="wlan0"
AP_CONN="SchoolAir_AP"
AP_SSID="SchoolAir_Setup"
AP_IP="192.168.4.1"
AP_CIDR="${AP_IP}/24"

# ── Output helpers ─────────────────────────────────────────────────────────────
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo; echo -e "${BOLD}▶ $*${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC}  $*"; }
die()   { echo -e "  ${RED}✗  ERROR: $*${NC}"; exit 1; }

# ── Pre-flight checks ──────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Must be run as root.  Try: sudo bash setup.sh"

command -v nmcli  >/dev/null 2>&1 || die "nmcli not found. Is NetworkManager installed?"
command -v python3 >/dev/null 2>&1 || die "python3 not found."

step "Pre-flight checks"
ok "Running as root"
ok "NetworkManager (nmcli) found"

if ! iw phy 2>/dev/null | grep -q "${AP_IFACE}" && ! ip link show "${AP_IFACE}" &>/dev/null; then
    warn "Interface ${AP_IFACE} not detected — continuing anyway (may be a VM or test run)"
fi

# ── 1. System packages ─────────────────────────────────────────────────────────
step "Installing system packages"
apt-get update -qq
apt-get install -y python3-pip avahi-daemon
ok "Packages installed"

# ── 2. Python dependencies ─────────────────────────────────────────────────────
step "Installing Python dependencies"
pip3 install --quiet -r "${SCRIPT_DIR}/requirements.txt"
python3 -c "import microdot" 2>/dev/null \
    && ok "microdot installed" \
    || die "microdot failed to import after pip install — check network or pip version"

# ── 3. Deploy wizard files ─────────────────────────────────────────────────────
step "Deploying wizard files to ${INSTALL_DIR}"
if [ "${SCRIPT_DIR}" = "${INSTALL_DIR}" ]; then
    ok "Source and install directory are the same — skipping copy"
else
    mkdir -p "${INSTALL_DIR}"
    # rsync-style copy: don't clobber a pre-existing config.py if it was edited
    for f in wizard.py launcher.sh requirements.txt \
              schoolair-launcher.service schoolair-wizard.service \
              PRD_v2.2.md CAPTIVE_PORTAL_SETUP.md; do
        cp "${SCRIPT_DIR}/${f}" "${INSTALL_DIR}/${f}"
    done
    # config.py: copy only if it doesn't already exist at the destination
    if [ ! -f "${INSTALL_DIR}/config.py" ]; then
        cp "${SCRIPT_DIR}/config.py" "${INSTALL_DIR}/config.py"
        ok "config.py copied (edit AP_CONNECTION_NAME if needed)"
    else
        ok "config.py already exists at destination — not overwritten"
    fi
fi
chmod +x "${INSTALL_DIR}/launcher.sh"
ok "launcher.sh is executable"

# ── 4. NetworkManager AP hotspot ───────────────────────────────────────────────
step "Configuring NetworkManager AP hotspot (${AP_SSID})"

if nmcli con show "${AP_CONN}" &>/dev/null; then
    nmcli con delete "${AP_CONN}" >/dev/null
    ok "Removed old '${AP_CONN}' connection"
fi

nmcli con add \
    type wifi \
    ifname "${AP_IFACE}" \
    con-name "${AP_CONN}" \
    wifi.mode ap \
    ssid "${AP_SSID}" \
    ipv4.method shared \
    ipv4.addresses "${AP_CIDR}" \
    connection.autoconnect no \
    >/dev/null

ok "Created NM hotspot connection '${AP_CONN}' on ${AP_IP}"

# ── 5. Captive-portal DNS hijack via NM dnsmasq ────────────────────────────────
step "Configuring captive-portal DNS hijacking"

mkdir -p /etc/NetworkManager/dnsmasq-shared.d
cat > /etc/NetworkManager/dnsmasq-shared.d/schoolair-captive.conf << EOF
# Resolve every hostname to this Pi so phones detect a captive portal.
address=/#/${AP_IP}
# Friendly mDNS-style alias (also handled by Avahi, but belt-and-suspenders).
address=/schoolair-register.local/${AP_IP}
EOF

systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager
ok "Captive-portal DNS config written and NM reloaded"

# ── 6. Avahi mDNS ──────────────────────────────────────────────────────────────
step "Configuring Avahi (schoolair-register.local)"

mkdir -p /etc/avahi/services
cat > /etc/avahi/services/schoolair.service << 'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>SchoolAir Registration Portal</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
  </service>
</service-group>
EOF

systemctl enable --quiet avahi-daemon
systemctl restart avahi-daemon
ok "Avahi service file installed and daemon restarted"

# ── 7. dhcpcd conflict prevention (Bullseye only) ──────────────────────────────
if [ -f /etc/dhcpcd.conf ]; then
    step "Preventing dhcpcd from interfering with wlan0 (Bullseye)"
    if grep -q "denyinterfaces ${AP_IFACE}" /etc/dhcpcd.conf; then
        ok "dhcpcd already configured to ignore ${AP_IFACE}"
    else
        printf '\n# SchoolAir — NetworkManager manages %s\ndenyinterfaces %s\n' \
            "${AP_IFACE}" "${AP_IFACE}" >> /etc/dhcpcd.conf
        ok "Added 'denyinterfaces ${AP_IFACE}' to /etc/dhcpcd.conf"
    fi
fi

# ── 8. Systemd services ────────────────────────────────────────────────────────
step "Installing systemd services"

cp "${INSTALL_DIR}/schoolair-launcher.service" /etc/systemd/system/
cp "${INSTALL_DIR}/schoolair-wizard.service"   /etc/systemd/system/
systemctl daemon-reload
systemctl enable schoolair-launcher.service
ok "schoolair-launcher.service installed and enabled"
ok "schoolair-wizard.service installed (started on demand by launcher)"

# ── 9. Verification ────────────────────────────────────────────────────────────
step "Verifying installation"
ERRORS=0

python3 -c "import microdot" 2>/dev/null \
    && ok "microdot importable" \
    || { warn "microdot not importable"; ERRORS=$((ERRORS+1)); }

[ -x "${INSTALL_DIR}/launcher.sh" ] \
    && ok "launcher.sh exists and is executable" \
    || { warn "launcher.sh missing or not executable"; ERRORS=$((ERRORS+1)); }

[ -f "${INSTALL_DIR}/wizard.py" ] \
    && ok "wizard.py present" \
    || { warn "wizard.py missing"; ERRORS=$((ERRORS+1)); }

nmcli con show "${AP_CONN}" &>/dev/null \
    && ok "NM hotspot connection '${AP_CONN}' exists" \
    || { warn "NM hotspot connection missing"; ERRORS=$((ERRORS+1)); }

[ -f /etc/NetworkManager/dnsmasq-shared.d/schoolair-captive.conf ] \
    && ok "Captive-portal dnsmasq config present" \
    || { warn "Captive-portal dnsmasq config missing"; ERRORS=$((ERRORS+1)); }

[ -f /etc/avahi/services/schoolair.service ] \
    && ok "Avahi service file present" \
    || { warn "Avahi service file missing"; ERRORS=$((ERRORS+1)); }

systemctl is-enabled schoolair-launcher.service &>/dev/null \
    && ok "schoolair-launcher.service enabled" \
    || { warn "schoolair-launcher.service not enabled"; ERRORS=$((ERRORS+1)); }

# ── Summary ────────────────────────────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$ERRORS" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}SchoolAir Gatekeeper setup complete.${NC}"
    echo    "  Reboot to activate:  sudo reboot"
else
    echo -e "  ${YELLOW}${BOLD}Setup finished with ${ERRORS} warning(s).${NC}"
    echo    "  Review the warnings above before rebooting."
fi
echo    "  Config file: ${INSTALL_DIR}/config.py"
echo    "  Logs after reboot: journalctl -u schoolair-launcher -u schoolair-wizard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
