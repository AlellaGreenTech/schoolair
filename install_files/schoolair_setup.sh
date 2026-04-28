#!/usr/bin/env bash
# SchoolAir – Full device setup script
# Lives at: install_files/schoolair_setup.sh in the repo.
#
# Run on a fresh Raspberry Pi OS Lite (Bullseye, Bookworm, or Trixie):
#
#   curl -sSL https://raw.githubusercontent.com/AlellaGreenTech/schoolair/main/install_files/schoolair_setup.sh \
#     | sudo bash
#
# To override the Pi username (default: admin):
#   curl ... | sudo ADMIN_USER=pi bash
#
# What this script does:
#   0.  Pre-flight checks
#   1.  Hostname  →  schoolair-YYMMDD-XXXX  (skipped if already set)
#   2.  System packages
#   3.  Clone SchoolAir repo to /tmp
#   4.  Python dependencies (microdot)
#   5.  Registration wizard files → ~/registration_wizard/
#   6.  i2c scripts + libraries → ~/i2c/
#   7.  Build sen6x daemon (if Makefile present)
#   8.  Node-RED config files → ~/.node-red/
#   9.  Node-RED + Node.js install
#   10. I2C enable + 100 kHz baudrate
#   11. NetworkManager Wi-Fi hotspot (SchoolAir_Setup, open)
#   12. Captive-portal DNS hijacking via NM dnsmasq plugin
#   13. Avahi  →  schoolair-register.local
#   14. dhcpcd conflict prevention (Bullseye only)
#   15. nginx  →  configured but DISABLED until registration
#   16. systemd services (launcher + wizard + any from etc/)
#   17. Cleanup + verification + summary
#
# Port-80 lifecycle:
#   Unregistered:  wizard (Microdot) holds port 80
#   Registered:    wizard exits, enables nginx → redirects port 80 to NR :1880
#
# Idempotent — safe to re-run.  Hostname is preserved once set.

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
# Override at runtime if your Pi user differs:  sudo ADMIN_USER=pi bash setup.sh
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

# ── Logging ───────────────────────────────────────────────────────────────────
# tee -a writes to both terminal and log file simultaneously — not either/or.
LOG_FILE="/var/log/schoolair-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "━━━ SchoolAir setup started: $(date) ━━━"

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

# ── 1. Hostname ────────────────────────────────────────────────────────────────
step "1 / Hostname"
# Pi OS Trixie ships with cloud-init (installed by Pi Imager).  cloud-init's
# cc_update_hostname module runs on EVERY boot with frequency=always and resets
# the hostname from its datasource — which it reads from a pickled instance
# cache, not directly from /boot/firmware/user-data.  Simply writing
# /etc/hostname is not enough; we must update four locations and wipe the
# instance cache so cloud-init re-reads the seed files on the next boot.

_set_hostname() {
    local hn="$1"
    # 1. The cloud-init seed file Pi Imager wrote (NoCloud datasource)
    if [ -f /boot/firmware/user-data ] && grep -q "^hostname:" /boot/firmware/user-data; then
        sed -i "s/^hostname:.*/hostname: ${hn}/" /boot/firmware/user-data
    fi
    # 2. cloud-init's previous-hostname cache (used by cc_update_hostname)
    mkdir -p /var/lib/cloud/data
    echo "$hn" > /var/lib/cloud/data/previous-hostname
    # 3. The file systemd-hostnamed reads at boot
    echo "$hn" > /etc/hostname
    # 4. /etc/hosts (manage_etc_hosts: true in user-data means cloud-init owns this)
    if grep -q "127\.0\.1\.1" /etc/hosts; then
        sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${hn}/" /etc/hosts
    else
        echo -e "127.0.1.1\t${hn}" >> /etc/hosts
    fi
    # 5. Wipe the pickled instance cache so cloud-init re-reads user-data fresh.
    #    Without this it ignores our changes to user-data and restores the old name.
    cloud-init clean 2>/dev/null || true
    # Set the live kernel UTS hostname for the current session
    hostname "$hn"
}

CURRENT_HN=$(hostname)
if [[ "$CURRENT_HN" == schoolair-* ]]; then
    ok "Hostname already set: ${CURRENT_HN}  (not regenerated)"
    # Still sync all four locations — a previous run may have set only the live
    # UTS hostname without persisting the underlying files.
    _HN_FILE=$(cat /etc/hostname 2>/dev/null | tr -d '[:space:]')
    if [ "$_HN_FILE" != "$CURRENT_HN" ]; then
        _set_hostname "$CURRENT_HN"
        ok "Hostname locations synced to ${CURRENT_HN}"
    fi
else
    # YYMMDD-XXXX where XXXX is the lower 16 bits of seconds-since-midnight in hex.
    # Modulo 65536 keeps the value to exactly 4 hex digits for any time of day.
    _midnight=$(date -d "$(date +%Y-%m-%d) 00:00:00" +%s)
    _secs=$(( $(date +%s) - _midnight ))
    NEW_HN="schoolair-$(date +%y%m%d)-$(printf '%04x' $(( _secs % 65536 )))"
    _set_hostname "$NEW_HN"
    ok "Hostname set to ${NEW_HN}"
fi

# ── 2. System packages ─────────────────────────────────────────────────────────
step "2 / System packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git python3-pip i2c-tools nginx avahi-daemon gcc make
ok "git python3-pip i2c-tools nginx avahi-daemon gcc make"

# apt-get install nginx auto-enables and starts the service on Debian systems.
# Kill it immediately so nothing holds port 80 before step 15 configures it.
systemctl disable nginx 2>/dev/null || true
systemctl stop    nginx 2>/dev/null || true

# ── 3. Clone repository ────────────────────────────────────────────────────────
step "3 / Clone SchoolAir repo"
# Compare the local HEAD SHA to the remote branch tip via git ls-remote (one
# network round trip, no object transfer).  Skip the clone if they match.
_REMOTE_SHA=$(git ls-remote "$REPO_URL" "refs/heads/${REPO_BRANCH}" 2>/dev/null | awk '{print $1}')
_LOCAL_SHA=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)
if [ -d "${REPO_DIR}/.git" ] \
   && [ -n "$_LOCAL_SHA" ] && [ -n "$_REMOTE_SHA" ] \
   && [ "$_LOCAL_SHA" = "$_REMOTE_SHA" ]; then
    skip "Repo already at latest commit ${_LOCAL_SHA:0:8} — not re-cloned"
else
    rm -rf "$REPO_DIR"
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR" \
        || die "git clone failed — check connectivity and repo URL."
    ok "Cloned to ${REPO_DIR}"
fi

# ── 4. Python dependencies ─────────────────────────────────────────────────────
step "4 / Python dependencies"
# --break-system-packages is required on Bookworm / Trixie (PEP 668).
# This Pi is a dedicated appliance; the flag is appropriate.
# microdot 2.x includes WebSocket support in the core package — no extra needed.
pip3 install --quiet --break-system-packages --root-user-action=ignore \
    "microdot>=2.0.0"
python3 -c "import microdot" 2>/dev/null \
    || die "microdot failed to import after install."
ok "microdot installed"

# ── 5. Registration wizard ─────────────────────────────────────────────────────
step "5 / Registration wizard  →  ${WIZARD_DIR}"
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

# ── 6. i2c scripts + libraries ────────────────────────────────────────────────
step "6 / i2c scripts + libraries  →  ${I2C_DIR}"
I2C_SRC="${INSTALL_FILES}/i2c"

if [ ! -d "$I2C_SRC" ]; then
    skip "install_files/i2c/ not in repo"
else
    mkdir -p "$I2C_DIR"
    # Stop any service running a compiled binary from this directory before
    # copying — the kernel refuses to overwrite an executing ELF (ETXTBSY).
    systemctl stop sen6x 2>/dev/null || true
    # Recursive copy — contains .sh, .py, and C source trees (MGSv2, o3, sen6x).
    # -u only overwrites if source is newer, preserving local edits.
    cp -ru "${I2C_SRC}/." "${I2C_DIR}/"
    find "$I2C_DIR" -name "*.sh" -exec chmod +x {} +
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "$I2C_DIR"
    ok "i2c directory deployed (recursive)"
fi

# ── 7. Build sen6x daemon ──────────────────────────────────────────────────────
step "7 / Build sen6x daemon"
MAKEFILE="${I2C_DIR}/sen6x/Makefile.daemon"

if [ ! -f "$MAKEFILE" ]; then
    skip "sen6x/Makefile.daemon not found"
else
    if make -C "${I2C_DIR}/sen6x" -f Makefile.daemon; then
        ok "sen6x daemon compiled"
    else
        warn "sen6x make failed — check gcc output above (non-fatal)"
    fi
fi

# ── 8. Node-RED config files ───────────────────────────────────────────────────
step "8 / Node-RED config files  →  ${NR_DIR}"
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

# ── 9. Node-RED + Node.js ──────────────────────────────────────────────────────
step "9 / Node-RED + Node.js"
# NodeSource only ships ARMv7+ (armhf) and ARM64 binaries.
# Pi Zero v1 is ARMv6 (armv6l) — a NodeSource binary will exist on disk but
# segfault at runtime.  We detect the architecture and use the unofficial
# armv6l builds from unofficial-builds.nodejs.org when needed.
#
# Node.js 20 LTS EOL: April 30, 2026.  Unofficial armv6l builds will receive
# no further security patches after that date.  For a closed school network
# this is low risk, but when iterating on the setup consider switching to
# Node 22 armv6l once unofficial-builds.nodejs.org makes it available.

_install_nodejs() {
    local arch; arch=$(uname -m)

    if [ "$arch" = "armv6l" ]; then
        echo "  ARMv6 detected (Pi Zero v1) — using unofficial Node.js armv6l build"
        # Remove any broken NodeSource install that may already be present
        apt-get remove -y nodejs 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/nodesource.list*
        # Remove stray binaries from every location apt / npm / tarballs use.
        # Prevents old ARMv7 ghosts from shadowing the new armv6l binary.
        rm -f /usr/bin/node /usr/bin/nodejs /usr/bin/npm /usr/bin/npx \
              /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx

        local ver
        ver=$(curl -sL https://nodejs.org/dist/index.json | \
              python3 -c "import sys,json; \
                r=[x for x in json.load(sys.stdin) if x['lts'] and x['version'].startswith('v20')]; \
                print(r[0]['version'].lstrip('v'))")
        [ -n "$ver" ] || die "Could not determine latest Node.js 20 LTS version."
        echo "  Downloading Node.js ${ver} for armv6l..."
        curl -fsSL \
          "https://unofficial-builds.nodejs.org/download/release/v${ver}/node-v${ver}-linux-armv6l.tar.xz" \
          -o /tmp/node-armv6l.tar.xz \
          || die "Node.js armv6l download failed."
        tar -xJf /tmp/node-armv6l.tar.xz -C /usr/local --strip-components=1
        rm -f /tmp/node-armv6l.tar.xz
        hash -r 2>/dev/null || true   # clear bash path cache so the new binary is found
        # Verify the installed binary actually runs (catches V8 JIT issues)
        /usr/local/bin/node --version >/dev/null 2>&1 \
            || die "Node.js armv6l binary installed but crashes on --version. Hardware incompatibility."
    else
        echo "  ARMv7/ARM64 detected — using NodeSource Node.js 20 LTS"
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
            || die "NodeSource repo setup failed."
        DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs \
            || die "nodejs install failed."
    fi
}

# A node binary that segfaults on --version is worse than no binary at all.
# Run the version check and treat a crash/empty result as "not installed".
_NODE_VER=$(node --version 2>/dev/null || true)
if [ -z "$_NODE_VER" ]; then
    echo "  (Installing Node.js 20 LTS — a few minutes...)"
    _install_nodejs
fi
ok "Node.js $(node --version) installed"

_NR_PKG="node-red"
if [ "$(uname -m)" = "armv6l" ]; then
    # Node-RED 4.x introduced @node-rs/bcrypt — a Rust pre-built binary that
    # ships only for armhf (ARMv7+).  It causes SIGILL on Pi Zero v1 (ARMv6).
    # Node-RED 3.x uses bcryptjs (pure JS) and works correctly on ARMv6.
    _NR_PKG="node-red@3"
fi

if ! command -v node-red >/dev/null 2>&1; then
    echo "  (Installing ${_NR_PKG} via npm — a few minutes...)"
    npm install -g --unsafe-perm "${_NR_PKG}" \
        || die "Node-RED npm install failed."
    _NR_VER=$(node-red --version 2>/dev/null | head -1 || true)
    [ -n "$_NR_VER" ] || _NR_VER="(version check failed — run 'node-red --version' to verify)"
    ok "Node-RED ${_NR_VER} installed"
else
    ok "Node-RED already installed — skipping"
fi

# Write a systemd unit for Node-RED running as the admin user.
# We do this ourselves rather than relying on the NR installer's init script.
NR_BIN="$(command -v node-red)"
cat > /etc/systemd/system/nodered.service << NREOF
[Unit]
Description=Node-RED
Documentation=http://nodered.org
After=network.target

[Service]
Type=simple
User=${ADMIN_USER}
WorkingDirectory=${ADMIN_HOME}
Environment="NODE_OPTIONS=--max-old-space-size=256"
ExecStart=${NR_BIN}
Restart=on-failure
KillSignal=SIGINT
SyslogIdentifier=Node-RED

[Install]
WantedBy=multi-user.target
NREOF
systemctl daemon-reload
systemctl enable nodered
ok "nodered.service installed and enabled for user '${ADMIN_USER}'"

if [ -f "${NR_DIR}/package.json" ]; then
    sudo -u "$ADMIN_USER" bash -c \
        "cd ${NR_DIR} && npm install --no-audit --no-fund --quiet"
    ok "Node-RED npm dependencies installed"
fi

# ── 10. I2C + baudrate ────────────────────────────────────────────────────────
step "10 / I2C enable + baudrate"
raspi-config nonint do_i2c 0
ok "I2C enabled (takes effect after reboot)"

# Trixie/Bookworm: /boot/firmware/config.txt  |  Bullseye: /boot/config.txt
if   [ -f /boot/firmware/config.txt ]; then CFG=/boot/firmware/config.txt
elif [ -f /boot/config.txt ];           then CFG=/boot/config.txt
else die "Cannot find config.txt — is this a Raspberry Pi?"; fi
ok "config.txt → ${CFG}"

# Always set 100 kHz explicitly — i2cdetect cannot run before I2C is activated
# (requires a reboot), so sensor detection is deferred here; 100 kHz is the
# standard speed and safe for all SchoolAir sensors.
sed -i '/dtparam=i2c_arm_baudrate/d' "$CFG"
echo "dtparam=i2c_arm_baudrate=100000" >> "$CFG"
ok "I2C baudrate → 100 kHz"

# ── 11. NM hotspot ────────────────────────────────────────────────────────────
step "11 / NetworkManager hotspot  (${AP_SSID})"
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

# ── 12. Captive-portal DNS ────────────────────────────────────────────────────
step "12 / Captive-portal DNS hijacking"
# NM's ipv4.method shared starts its own dnsmasq; we inject options via the
# dnsmasq-shared.d plugin dir.  address=/#/... forces every DNS query to return
# the Pi's IP, triggering the captive-portal dialog on iOS and Android.
mkdir -p /etc/NetworkManager/dnsmasq-shared.d
cat > /etc/NetworkManager/dnsmasq-shared.d/schoolair-captive.conf << EOF
address=/#/${AP_IP}
address=/schoolair-register.local/${AP_IP}
EOF
systemctl reload NetworkManager 2>/dev/null || systemctl restart NetworkManager
ok "Captive-portal DNS config written"

# ── 13. Avahi ─────────────────────────────────────────────────────────────────
step "13 / Avahi  →  schoolair-register.local"
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

# ── 14. dhcpcd (Bullseye only) ────────────────────────────────────────────────
if [ -f /etc/dhcpcd.conf ]; then
    step "14 / dhcpcd conflict prevention  (Bullseye)"
    if grep -q "denyinterfaces ${AP_IFACE}" /etc/dhcpcd.conf; then
        ok "Already configured"
    else
        printf '\n# SchoolAir — NetworkManager manages %s\ndenyinterfaces %s\n' \
            "$AP_IFACE" "$AP_IFACE" >> /etc/dhcpcd.conf
        ok "Added denyinterfaces ${AP_IFACE}"
    fi
fi

# ── 15. nginx ─────────────────────────────────────────────────────────────────
step "15 / nginx  (configured, disabled until registration)"
# nginx redirects port 80 → Node-RED (:1880) once the device is registered.
# Stays disabled here — wizard.py's _delayed_shutdown() enables it on success,
# activating it for all future boots.
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

# ── 16. systemd services ──────────────────────────────────────────────────────
step "16 / systemd services"

# 16a. Any .service files under install_files/etc/systemd/system/ (e.g. sen6x)
ETC_SYSTEMD="${INSTALL_FILES}/etc/systemd/system"
if [ -d "$ETC_SYSTEMD" ]; then
    for svc in "${ETC_SYSTEMD}"/*.service; do
        [ -f "$svc" ] || continue
        name="$(basename "$svc")"
        cp "$svc" /etc/systemd/system/
        systemctl enable "$name" 2>/dev/null || true
        ok "${name} installed + enabled"
    done
fi

# 16b. Registration wizard services (stored alongside the wizard, not in etc/)
if [ -d "$WIZARD_DIR" ] \
   && [ -f "${WIZARD_DIR}/schoolair-launcher.service" ] \
   && [ -f "${WIZARD_DIR}/schoolair-wizard.service" ]; then
    cp "${WIZARD_DIR}/schoolair-launcher.service" /etc/systemd/system/
    cp "${WIZARD_DIR}/schoolair-wizard.service"   /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable schoolair-launcher.service
    # Wizard service intentionally NOT enabled — launcher starts it on demand.
    ok "schoolair-launcher.service enabled"
    ok "schoolair-wizard.service installed (on-demand only)"
else
    warn "Wizard service files missing — schoolair systemd services not installed"
fi

systemctl daemon-reload

# ── 17. Cleanup ───────────────────────────────────────────────────────────────
step "17 / Cleanup"
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

chk "hostname is schoolair-*"              bash -c '[[ "$(hostname)" == schoolair-* ]]'
chk "microdot importable"                  python3 -c "import microdot"
chk "node-red in PATH"                     command -v node-red
chk "launcher.sh executable"              test -x "${WIZARD_DIR}/launcher.sh"
chk "wizard.py present"                   test -f "${WIZARD_DIR}/wizard.py"
chk "i2c dir present"                     test -d "${I2C_DIR}"
chk "NM hotspot '${AP_CONN}'"             nmcli con show "$AP_CONN"
chk "Captive-portal DNS config"           test -f /etc/NetworkManager/dnsmasq-shared.d/schoolair-captive.conf
chk "Avahi service file"                  test -f /etc/avahi/services/schoolair.service
chk "schoolair-launcher enabled"          systemctl is-enabled schoolair-launcher.service
chk "nginx has 1880 redirect"             grep -q 1880 /etc/nginx/sites-available/default
chk "nginx disabled (correct pre-reg)"    bash -c "! systemctl is-enabled nginx >/dev/null 2>&1"
chk "sen6x.service enabled"              systemctl is-enabled sen6x.service

# ── Summary ────────────────────────────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$ERRORS" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}Setup complete — all checks passed.${NC}"
else
    echo -e "  ${YELLOW}${BOLD}Setup complete with ${ERRORS} warning(s) — see above.${NC}"
fi
echo
echo "  This device hostname:  $(hostname)"
echo
echo "  Pending before rebooting:"
[ ! -d "${INSTALL_FILES}/.node-red" ] 2>/dev/null \
    && echo -e "  ${YELLOW}➜${NC}  Node-RED flows not in repo — add install_files/.node-red/ and re-run" \
    || true
[ ! -d "$WIZARD_DIR" ] 2>/dev/null \
    && echo -e "  ${YELLOW}➜${NC}  Wizard not deployed — add install_files/registration_wizard/ and re-run" \
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
echo
echo "  Developer notes (re-run only):"
echo -e "  ${YELLOW}➜${NC}  sen6x daemon was stopped to allow binary replacement."
echo "     Start it now without rebooting:  sudo systemctl start sen6x"
echo "     Or simply reboot — it starts automatically on boot."
echo -e "  ${YELLOW}➜${NC}  Node.js 20 LTS EOL: April 30 2026. Consider upgrading to Node 22"
echo "     armv6l once unofficial-builds.nodejs.org makes it available."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
