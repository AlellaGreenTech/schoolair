# Captive Portal Infrastructure Setup

> **Most deployments only need to read §1–§3.**
> `setup.sh` automates all of these steps.  This document explains *why* each
> piece exists and provides manual commands for debugging or re-running
> individual steps.

---

## Overview

When a phone joins `SchoolAir_Setup`, it sends an HTTP probe to a known URL
(e.g. `connectivitycheck.gstatic.com` on Android, `captive.apple.com` on iOS).
The Pi intercepts this probe by:

1. **NetworkManager hotspot** — broadcasts `SchoolAir_Setup` and assigns IP
   addresses to connecting phones via DHCP.
2. **NM dnsmasq captive-portal plugin** — resolves every DNS query to
   `192.168.4.1`, causing the phone to detect a captive portal and pop up the
   browser.
3. **Avahi** — advertises `schoolair-register.local` so staff can also navigate
   to the portal by name.

All three are handled by `setup.sh`.  Manual steps are shown below.

---

## 1. NetworkManager Hotspot

`setup.sh` creates a NetworkManager connection called `SchoolAir_AP` that
broadcasts the `SchoolAir_Setup` open Wi-Fi network.  Using NM (rather than
raw hostapd) allows the same `wlan0` interface to be used for both the AP and
client connections — which is required for the registration flow.

**What setup.sh runs:**
```bash
nmcli con add \
    type wifi ifname wlan0 con-name SchoolAir_AP \
    wifi.mode ap ssid SchoolAir_Setup \
    ipv4.method shared \
    ipv4.addresses 192.168.4.1/24 \
    connection.autoconnect no
```

`connection.autoconnect no` is intentional: the launcher script (`launcher.sh`)
brings up the AP only when needed, so a registered device never broadcasts the
setup network on boot.

**To bring up or tear down the AP manually:**
```bash
nmcli con up   SchoolAir_AP
nmcli con down SchoolAir_AP
```

**To verify the hotspot is running:**
```bash
nmcli -t -f NAME,STATE con show --active | grep SchoolAir_AP
# Expected: SchoolAir_AP:activated
iw dev wlan0 info | grep ssid
# Expected: ssid SchoolAir_Setup
```

---

## 2. Captive-Portal DNS Hijacking

NM's `ipv4.method shared` mode starts its own dnsmasq instance to serve DHCP
on the hotspot interface.  That instance reads extra options from
`/etc/NetworkManager/dnsmasq-shared.d/`.

**What setup.sh writes to
`/etc/NetworkManager/dnsmasq-shared.d/schoolair-captive.conf`:**
```ini
address=/#/192.168.4.1
address=/schoolair-register.local/192.168.4.1
```

`address=/#/192.168.4.1` tells dnsmasq to return `192.168.4.1` for every DNS
query, including the connectivity check probes that trigger the captive-portal
dialog on iOS and Android.

**To verify DNS hijacking is working** (while a phone is connected to the AP):
```bash
dig @192.168.4.1 connectivitycheck.gstatic.com +short
# Expected: 192.168.4.1
```

---

## 3. Avahi mDNS (`schoolair-register.local`)

Avahi advertises the portal over mDNS so staff with mDNS-capable devices can
type `http://schoolair-register.local` instead of `http://192.168.4.1`.

Note: mDNS resolution is unreliable on Android in captive-portal mode.  The
IP address `http://192.168.4.1` always works as a fallback.

**What setup.sh writes to `/etc/avahi/services/schoolair.service`:**
```xml
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>SchoolAir Registration Portal</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
  </service>
</service-group>
```

**To verify mDNS:**
```bash
avahi-resolve -n schoolair-register.local
# Expected: schoolair-register.local  192.168.4.1
```

---

## 4. dhcpcd Conflict (Raspberry Pi OS Bullseye only)

On Bullseye, both `dhcpcd` and NetworkManager are installed.  If dhcpcd tries
to run DHCP on `wlan0`, it fights with NM's hotspot.  `setup.sh` automatically
adds `denyinterfaces wlan0` to `/etc/dhcpcd.conf` when this file is detected
(Bullseye).  On Bookworm, dhcpcd is absent and this step is skipped.

---

## 5. Full Setup Verification

Run after `setup.sh` and after a reboot to confirm everything is working:

```bash
# 1. Launcher ran and started the wizard
journalctl -u schoolair-launcher --no-pager | tail -5
journalctl -u schoolair-wizard   --no-pager | tail -5

# 2. AP is broadcasting
nmcli -t -f NAME,STATE con show --active | grep SchoolAir_AP

# 3. DNS hijacking works (while phone is on the AP)
dig @192.168.4.1 google.com +short    # → 192.168.4.1

# 4. Portal is serving HTTP
curl -s http://192.168.4.1/ | grep -o "SchoolAir Setup"

# 5. mDNS resolves
avahi-resolve -n schoolair-register.local
```

---

## 6. Boot Sequence

```
Pi boots
  └─ NetworkManager starts
  └─ avahi-daemon starts → schoolair-register.local resolves
  └─ schoolair-launcher.service (oneshot)
       ├─ status.json present? → exit 0 (registered device, nothing to do)
       ├─ client Wi-Fi connects in 60 s? → exit 0
       └─ nmcli con up SchoolAir_AP
          sleep 3
          systemctl start schoolair-wizard
               └─ wizard.py listens on 0.0.0.0:80
                  NM dnsmasq captive-portal config active
                  phones detect portal and open browser
```

---

## 7. Alternative: hostapd-Managed AP

> Use this only if NM hotspot mode is unreliable on your specific hardware.
> **Requires manual edits to `config.py` and `wizard.py`.**

The NM approach (above) is preferred because it lets NM manage both the AP and
client connections on the same interface — the critical requirement for the
wizard's registration flow.

If you must use hostapd:

1. Tell NM not to manage `wlan0`:
   ```bash
   cat > /etc/NetworkManager/conf.d/99-unmanaged-wlan0.conf << 'EOF'
   [keyfile]
   unmanaged-devices=interface-name:wlan0
   EOF
   systemctl reload NetworkManager
   ```

2. Set a static IP for `wlan0` in `/etc/dhcpcd.conf`:
   ```
   interface wlan0
   static ip_address=192.168.4.1/24
   nohook wpa_supplicant
   ```

3. Install and configure hostapd:
   ```bash
   apt-get install hostapd
   cat > /etc/hostapd/hostapd.conf << 'EOF'
   interface=wlan0
   driver=nl80211
   ssid=SchoolAir_Setup
   hw_mode=g
   channel=6
   auth_algs=1
   EOF
   systemctl unmask hostapd && systemctl enable hostapd && systemctl start hostapd
   ```

4. Install standalone dnsmasq for captive-portal:
   ```bash
   apt-get install dnsmasq
   cat > /etc/dnsmasq.d/schoolair.conf << 'EOF'
   interface=wlan0
   dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h
   address=/#/192.168.4.1
   address=/schoolair-register.local/192.168.4.1
   EOF
   systemctl enable dnsmasq && systemctl start dnsmasq
   ```

5. **Critical:** because NM no longer manages `wlan0`, the wizard cannot use
   `nmcli` to connect to school Wi-Fi.  You must switch `wizard.py` to use
   `wpa_supplicant` directly, which is a significant code change not covered
   here.
