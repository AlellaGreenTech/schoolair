#!/usr/bin/env bash
# SchoolAir – Full device setup script
# Lives at: install_files/schoolair_setup.sh in the repo.
#
# Run on a fresh Raspberry Pi OS Lite (Bullseye or Bookworm):
#
#   curl -sSL https://raw.githubusercontent.com/AlellaGreenTech/schoolair/main/install_files/schoolair_setup.sh \
#     | sudo bash
#
# To override the Pi username (default: admin):
#   curl ... | sudo ADMIN_USER=pi bash
#
# What this script does:
#   0.  Pre-flight checks
#   1.  System packages
#   2.  Clone SchoolAir repo to /tmp
#   3.  Python dependencies (microdot)
#   4.  Registration wizard files → ~/registration_wizard/
#   5.  i2c scripts + libraries → ~/i2c/
#   6.  Build sen6x daemon (if Makefile present)
#   7.  Node-RED config files → ~/.node-red/
#   8.  Node-RED + Node.js install
#   9.  I2C enable + 100 kHz baudrate
#   10. NetworkManager Wi-Fi hotspot (SchoolAir_Setup, open)
#   11. Captive-portal DNS hijacking via NM dnsmasq plugin
#   12. Avahi  →  schoolair-register.local
#   13. dhcpcd conflict prevention (Bullseye only)
#   14. nginx  →  configured but DISABLED until registration
#   15. systemd services (launcher + wizard + any from etc/)
#   16. Cleanup + verification + summary
#
# Port-80 lifecycle:
#   Unregistered:  wizard (Microdot) holds port 80
#   Registered:    wizard exits, enables nginx → redirects port 80 to NR :1880

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_HOME="/home/${ADMIN_USER}"

REPO_URL="https://github.com/AlellaGreenTech/schoolair.git"
REPO_BRANCH="main"
REPO_DIR="/tmp/schoolair"
INSTALL_FILES="${REPO_DIR}/install_files"

WIZARD_DIR="${ADMIN_HOME}/registration_wizard"
I2C_DIR="${ADMIN_HOME}/i2c"
NR_DIR="${ADMIN_HOME}/.node-red"

AP_IFACE="wlan0"
AP_CONN="SchoolAir_AP"
AP_SSID="SchoolAir_Setup"
AP_IP="192.168.4.1"

# ── Helpers ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo; echo -e "${BOLD}── $* ──${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC}  $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC}   $*"; }
skip()  { echo -e "  –   $* (skipped)"; }
die()   { echo -e "${RED}${BOLD}FATAL: $*${NC}"; exit 1; }

# ── 0. Pre-flight ──────────────────────────────────────────────────────────────
step "0 / Pre-flight"
[[ $EUID -eq 0 ]] \
    || die "Must run as root.  Try:  sudo bash $0"
id -u "$ADMIN_USER" >/dev/null 2>&1 \
    || die "User '${ADMIN_USER}' not found.  Set ADMIN_USER=<name> and re-run."
command -v nmcli   >/dev/null 2>&1 || die "nmcli not found — is NetworkManager installed?"
command -v python3 >/dev/null 2>&1 || die "python3 not found."
ok "Root, user='${ADMIN_USER}', home='${ADMIN_HOME}'"

# ── 1. System packages ─────────────────────────────────────────────────────────
step "1 / System packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git python3-pip i2c-tools nginx avahi-daemon gcc make
ok "git python3-pip i2c-tools nginx avahi-daemon gcc make"

# ── 2. Clone repository ────────────────────────────────────────────────────────
step "2 / Clone SchoolAir repo"
rm -rf "$REPO_DIR"
git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR" \
    || die "git clone failed — check connectivity and repo URL."
ok "Cloned to ${REPO_DIR}"

# ── 3. Python dependencies ─────────────────────────────────────────────────────
step "3 / Python dependencies"
pip3 install --quiet "microdot[websocket]>=2.0.0"
python3 -c "import microdot" 2>/dev/null \
    || die "microdot failed to import after install."
ok "microdot installed"

# ── 4. Registration wizard ─────────────────────────────────────────────────────
step "4 / Registration wizard  →  ${WIZARD_DIR}"
WIZARD_SRC="${INSTALL_FILES}/registration_wizard"

if [ ! -d "$WIZARD_SRC" ]; then
    warn "install_files/registration_wizard/ not in repo — wizard NOT deployed."
    warn "Commit the wizard files there and re-run."
else
    mkdir -p "$WIZARD_DIR"
    if [ ! -f "${WIZARD_DIR}/config.py" ]; then
        # Fresh install — copy everything, including config.py
        cp -r "${WIZARD_SRC}/." "${WIZARD_DIR}/"
        ok "All wizard files deployed (including config.py)"
    else
        # Re-run — update runtime files; preserve any hand-edited config.py
        for f in wizard.py launcher.sh schoolair_setup.sh \
                  schoolair-launcher.service schoolair-wizard.service \
                  requirements.txt; do
            [ -f "${WIZARD_SRC}/${f}" ] && cp "${WIZARD_SRC}/${f}" "${WIZARD_DIR}/${f}"
        done
        ok "Wizard runtime files updated (config.py preserved)"
    fi
    chmod +x "${WIZARD_DIR}/launcher.sh"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "$WIZARD_DIR"
fi

# ── 5. i2c scripts + libraries ────────────────────────────────────────────────
step "5 / i2c scripts + libraries  →  ${I2C_DIR}"
I2C_SRC="${INSTALL_FILES}/i2c"

if [ ! -d "$I2C_SRC" ]; then
    skip "install_files/i2c/ not in repo"
else
    mkdir -p "$I2C_DIR"
    # Full recursive copy — the i2c dir contains .sh, .py, and C source trees.
    # -u preserves files the user may have edited locally if source is not newer.
    cp -ru "${I2C_SRC}/." "${I2C_DIR}/"
    # Make all shell scripts executable
    find "$I2C_DIR" -name "*.sh" -exec chmod +x {} +
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "$I2C_DIR"
    ok "i2c directory deployed (recursive)"
fi

# ── 6. Build sen6x daemon ──────────────────────────────────────────────────────
step "6 / Build sen6x daemon"
MAKEFILE="${I2C_DIR}/sen6x/Makefile.daemon"

if [ ! -f "$MAKEFILE" ]; then
    skip "sen6x/Makefile.daemon not found"
else
    make -C "${I2C_DIR}/sen6x" -f Makefile.daemon \
        || { warn "sen6x make failed — check gcc output above"; }
    ok "sen6x daemon compiled"
fi

# ── 7. Node-RED config files ───────────────────────────────────────────────────
step "7 / Node-RED config files  →  ${NR_DIR}"
NR_SRC="${INSTALL_FILES}/.node-red"

if [ ! -d "$NR_SRC" ]; then
    skip "install_files/.node-red/ not in repo"
else
    mkdir -p "$NR_DIR"
    # flows.json: never overwrite — protects existing device flows
    if cp -n "${NR_SRC}/flows.json" "${NR_DIR}/flows.json" 2>/dev/null; then
        ok "flows.json deployed"
    else
        ok "flows.json already present — not overwritten"
    fi
    cp -u "${NR_SRC}/settings.js"  "${NR_DIR}/settings.js"
    cp -u "${NR_SRC}/package.json" "${NR_DIR}/package.json"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "$NR_DIR"
    ok "settings.js, package.json deployed"
fi

# ── 8. Node-RED + Node.js ──────────────────────────────────────────────────────
step "8 / Node-RED + Node.js"
if command -v node-red >/dev/null 2>&1; then
    ok "Node-RED already installed — skipping"
else
    # Official installer — handles Pi detection and enables nodered.service.
    # Run as admin so ~/.node-red and npm cache land in the correct home.
    sudo -u "$ADMIN_USER" bash -c \
        "curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered \
        | bash -s -- --confirm-install --confirm-pi" \
        || die "Node-RED installation failed."
    ok "Node-RED installed"
fi

if [ -f "${NR_DIR}/package.json" ]; then
    sudo -u "$ADMIN_USER" bash -c \
        "cd ${NR_DIR} && npm install --no-audit --no-fund --quiet"
    ok "Node-RED npm dependencies installed"
fi

# ── 9. I2C + baudrate ─────────────────────────────────────────────────────────
step "9 / I2C enable + baudrate"
raspi-config nonint do_i2c 0
ok "I2C enabled (takes effect after reboot)"

# Bookworm moved config.txt to /boot/firmware/
if   [ -f /boot/firmware/config.txt ]; then CFG=/boot/firmware/config.txt
elif [ -f /boot/config.txt ];           then CFG=/boot/config.txt
else die "Cannot find config.txt — is this a Raspberry Pi?"; fi
ok "config.txt → ${CFG}"

# Always set 100 kHz explicitly — the correct speed for all SchoolAir sensors.
# i2cdetect cannot run before I2C is activated (requires a reboot), so sensor
# detection is deferred; 100 kHz is safe and backward-compatible.
sed -i '/dtparam=i2c_arm_baudrate/d' "$CFG"
echo "dtparam=i2c_arm_baudrate=100000" >> "$CFG"
ok "I2C baudrate → 100 kHz"

# ── 10. NM hotspot ────────────────────────────────────────────────────────────
step "10 / NetworkManager hotspot  (${AP_SSID})"
if nmcli con show "$AP_CONN" &>/dev/null; then
    nmcli con delete "$AP_CONN" >/dev/null
fi
nmcli con add           \
    type wifi           \
    ifname "$AP_IFACE"  \
    con-name "$AP_CONN" \
    wifi.mode ap        \
    ssid "$AP_SSID"     \
    ipv4.method shared  \
    ipv4.addresses "${AP_IP}/24" \
    connection.autoconnect no   \
    >/dev/null
# autoconnect no: launcher.sh brings the AP up only when registration is needed.
ok "Open hotspot on ${AP_IP}  (autoconnect disabled — launcher controls it)"

# ── 11. Captive-portal DNS ────────────────────────────────────────────────────
step "11 / Captive-portal DNS hijacking"
# NM's 'ipv4.method shared' starts its own dnsmasq; we inject options via the
# dnsmasq-shared.d plugin dir.  address=/#/... forces every DNS query to return
# the Pi's IP, triggering the captive-portal dialog on iOS and Android.
mkdir -p /etc/NetworkManager/dnsmasq-shared.d
cat > /etc/NetworkManager/dnsmasq-shared.d/schoolair-captive.conf << EOF
address=/#/${AP_IP}
address=/schoolair-register.local/${AP_IP}
EOF
systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager
ok "Captive-portal DNS config written"

# ── 12. Avahi ─────────────────────────────────────────────────────────────────
step "12 / Avahi  →  schoolair-register.local"
mkdir -p /etc/avahi/services
cat > /etc/avahi/services/schoolair.service << 'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>SchoolAir Registration Portal</name>
  <service><type>_http._tcp</type><port>80</port></service>
</service-group>
EOF
systemctl enable --quiet avahi-daemon
systemctl restart avahi-daemon
ok "Avahi configured"

# ── 13. dhcpcd (Bullseye only) ────────────────────────────────────────────────
if [ -f /etc/dhcpcd.conf ]; then
    step "13 / dhcpcd conflict prevention  (Bullseye)"
    if grep -q "denyinterfaces ${AP_IFACE}" /etc/dhcpcd.conf; then
        ok "Already configured"
    else
        printf '\n# SchoolAir — NetworkManager manages %s\ndenyinterfaces %s\n' \
            "$AP_IFACE" "$AP_IFACE" >> /etc/dhcpcd.conf
        ok "Added denyinterfaces ${AP_IFACE}"
    fi
fi

# ── 14. nginx ─────────────────────────────────────────────────────────────────
step "14 / nginx  (configured, disabled until registration)"
# nginx redirects port 80 → Node-RED (:1880) once the device is registered.
# It deliberately stays disabled here — wizard.py's _delayed_shutdown() runs
#   systemctl enable nginx && systemctl start nginx
# on successful registration, activating it for all future boots.
cat > /etc/nginx/sites-available/default << 'NGINXEOF'
server {
    listen 80;
    server_name _;
    location / {
        return 301 http://$host:1880/ui;
    }
}
NGINXEOF
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
systemctl disable nginx 2>/dev/null || true
systemctl stop    nginx 2>/dev/null || true
ok "nginx config written  (service disabled)"

# ── 15. systemd services ──────────────────────────────────────────────────────
step "15 / systemd services"

# 15a. Services from install_files/etc/systemd/system/ (e.g. sen6x.service)
ETC_SYSTEMD="${INSTALL_FILES}/etc/systemd/system"
if [ -d "$ETC_SYSTEMD" ]; then
    for svc in "${ETC_SYSTEMD}"/*.service; do
        [ -f "$svc" ] || continue
        name="$(basename "$svc")"
        cp "$svc" /etc/systemd/system/
        systemctl enable "$name" 2>/dev/null && ok "${name} installed + enabled"
    done
fi

# 15b. Registration wizard services (from wizard dir, not etc/)
if [ -d "$WIZARD_DIR" ]; then
    cp "${WIZARD_DIR}/schoolair-launcher.service" /etc/systemd/system/
    cp "${WIZARD_DIR}/schoolair-wizard.service"   /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable schoolair-launcher.service
    # Wizard service intentionally NOT enabled — launcher starts it on demand.
    ok "schoolair-launcher.service enabled"
    ok "schoolair-wizard.service installed (on-demand)"
else
    warn "Wizard dir missing — schoolair systemd services not installed"
fi

systemctl daemon-reload

# ── 16. Cleanup ───────────────────────────────────────────────────────────────
step "16 / Cleanup"
rm -rf "$REPO_DIR"
ok "Temp repo removed"

# ── Verification ───────────────────────────────────────────────────────────────
step "Verification"
ERRORS=0
chk() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$label"
    else warn "$label"; ERRORS=$((ERRORS+1)); fi
}

chk "microdot importable"                   python3 -c "import microdot"
chk "node-red in PATH"                      command -v node-red
chk "launcher.sh executable"               test -x "${WIZARD_DIR}/launcher.sh"
chk "wizard.py present"                    test -f "${WIZARD_DIR}/wizard.py"
chk "i2c dir present"                      test -d "${I2C_DIR}"
chk "NM hotspot '${AP_CONN}'"              nmcli con show "$AP_CONN"
chk "Captive-portal DNS config"            test -f /etc/NetworkManager/dnsmasq-shared.d/schoolair-captive.conf
chk "Avahi service file"                   test -f /etc/avahi/services/schoolair.service
chk "schoolair-launcher enabled"           systemctl is-enabled schoolair-launcher.service
chk "nginx has 1880 redirect"              grep -q 1880 /etc/nginx/sites-available/default
chk "nginx disabled (correct at this stage)" bash -c "! systemctl is-enabled nginx >/dev/null 2>&1"
chk "sen6x.service enabled"               systemctl is-enabled sen6x.service

# ── Summary ────────────────────────────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$ERRORS" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}Setup complete — all checks passed.${NC}"
else
    echo -e "  ${YELLOW}${BOLD}Setup complete with ${ERRORS} warning(s) — see above.${NC}"
fi
echo
echo "  Checklist before rebooting:"
[ ! -d "${INSTALL_FILES}/.node-red" ] \
    && echo -e "  ${YELLOW}➜  Node-RED flows not in repo yet${NC} — add install_files/.node-red/ and re-run"
[ ! -d "${WIZARD_DIR}" ] 2>/dev/null \
    && echo -e "  ${YELLOW}➜  Wizard not deployed${NC} — add install_files/registration_wizard/ and re-run" \
    || true
echo
echo "  After rebooting:"
echo "  1. Join Wi-Fi:  SchoolAir_Setup  (open, no password)"
echo "  2. Open:        http://${AP_IP}"
echo "  3. Complete the registration form."
echo "  4. On success the hotspot closes; nginx activates on port 80."
echo
echo "  Logs:"
echo "    journalctl -u schoolair-launcher -u schoolair-wizard -f"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
