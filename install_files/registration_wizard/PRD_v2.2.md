# SchoolAir "Gatekeeper" Registration Portal — PRD v2.2

> Supersedes PRD v2.1.  Changes summarised in §0.

---

## Notes For Testing:

# disconnect form current wifi and reboot to start the Wizard:
sudo nmcli connection delete <SSID> && sudo reboot

## 0. Changes from v2.1

| # | Topic | v2.1 | v2.2 |
|---|-------|------|------|
| A | Storage path | Conflicting (§1 vs §5) | Unified: `/home/admin/.config/schoolair/` |
| B | Heartbeat endpoint | Undefined | `POST https://data.schoolair.org/aqc/register` |
| C | Pi Zero v1 support | Assumed concurrent mode | Graceful degradation (§4.1) |
| D | Real-time UI comms | "Long Poll or WebSocket" | WebSocket (Microdot native) |
| E | AP shutdown timing | Immediate | 6-second grace window after success signal |
| F | Captive portal setup | Described inline | Separate guide: `CAPTIVE_PORTAL_SETUP.md` |

---

## 1. Core Principle

Identity and connectivity are a single atomic transaction.  The device
broadcasts as an Access Point and serves the registration portal until a
successful heartbeat with the SchoolAir Cloud is confirmed.

---

## 2. State & Storage

All paths live under `/home/admin/.config/schoolair/`.

| File | Created | Deleted | Purpose |
|------|---------|---------|---------|
| `staging.json` | On form submit | On heartbeat success | Persist form data across reboots |
| `status.json` | On heartbeat success | Never | Proof of registration; drives launcher logic |
| `last_error.txt` | On any failure | Manually or on re-registration | Debugging aid |

**Atomic writes:** files are written to a `.tmp` sibling and then `os.replace`'d
to prevent partial reads on power loss.

### staging.json schema

```json
{
  "token":       "SA-2024-XXXXX",
  "site":        "Lincoln Elementary",
  "asset_name":  "Room 302",
  "environment": "indoor",
  "ssid":        "SchoolNet",
  "password":    "wpa-psk-passphrase"
}
```

### status.json schema

```json
{
  "token":         "SA-2024-XXXXX",
  "site":          "Lincoln Elementary",
  "asset_name":    "Room 302",
  "environment":   "indoor",
  "ssid":          "SchoolNet",
  "registered_at": "2024-09-01T08:32:11+00:00"
}
```

---

## 3. User Flow

### Phase 1 — Interaction

1. User joins `SchoolAir_Setup` Wi-Fi.
2. Captive portal opens automatically (via dnsmasq redirect — see
   `CAPTIVE_PORTAL_SETUP.md`) or user navigates to
   `http://schoolair-register.local`.
3. Single-page form collects:
   - **Token** — registration token
   - **Site** — school / organisation name
   - **Asset Name** — e.g. "Room 302"
   - **Environment** — Indoor / Outdoor toggle
   - **SSID** — target school Wi-Fi network name
   - **Password** — WPA Personal passphrase
4. Previously entered data is pre-filled from `staging.json` if a prior
   attempt was interrupted (power loss, etc.).  Password is **not** pre-filled
   for security; the user re-enters it.

### Phase 2 — Heartbeat Confirmation

After the user clicks "Register & Connect":

1. `staging.json` is written.
2. The browser transitions to the **Live Progress** screen and opens a
   WebSocket to `/ws/status`.
3. The backend:
   a. Creates a NetworkManager client profile for the target SSID.
   b. Issues `nmcli con up` — this may drop the AP on Pi Zero v1 (see §4.1).
   c. Waits up to 30 s for an IP address.
   d. POSTs the registration payload to the heartbeat endpoint.
4. **Success path:** `status.json` written, `staging.json` deleted, success
   message pushed over WebSocket, AP shuts down after 6 s.
5. **Failure path:** AP restored, error message pushed over WebSocket (or
   shown on page reload), user can correct and retry.

---

## 4. Technical Architecture

### 4.1 Pi Zero v1 Concurrent-Mode Strategy

The original Pi Zero W (BCM43438) has a single Wi-Fi chip.  Unlike the
Pi 3/4/Zero 2W, it **cannot reliably maintain the AP and a Station
connection simultaneously**.

**Behaviour on Pi Zero v1:**
- When `nmcli con up schoolair-client` executes, the AP will drop.
- The browser's WebSocket connection closes.
- The browser JS detects the close and shows:
  > "The setup hotspot dropped — the device is connecting to the school
  > Wi-Fi.  If successful, registration is complete.  If the hotspot
  > reappears within 60 seconds, tap Try Again to review the error."
- If the heartbeat fails, the Pi reverts to AP mode and the browser
  reconnects automatically (JS retries WebSocket every 3 s), then
  shows the error.
- If the heartbeat succeeds, the AP stays down permanently — the user's
  phone will eventually connect to the school Wi-Fi or their normal network.

**Why this is still viable:**  the user receives clear feedback in both
outcome paths without the Pi needing to tell the phone "I succeeded" over
the AP link.

### 4.2 Heartbeat Endpoint

```
POST https://data.schoolair.org/aqc/register
Content-Type: application/json

{
  "token":        "<string>",
  "site":         "<string>",
  "asset_name":   "<string>",
  "environment":  "indoor" | "outdoor",
  "ssid":         "<string>",
  "registered_at":"<ISO 8601 UTC>"
}
```

Expected response on success: `HTTP 200`.
`HTTP 401` / `403` → "Token rejected by SchoolAir Cloud".
Any other error → generic failure message; AP reverts.

### 4.3 Conditional Systemd Logic

```
boot
 └─ schoolair-launcher.service  (oneshot)
      ├─ status.json exists?  → exit 0
      ├─ Wi-Fi connected in 60 s? → exit 0
      └─ otherwise → systemctl start schoolair-wizard.service
```

`schoolair-wizard.service` is **not** set to `WantedBy=multi-user.target`
by default — it is started on demand by the launcher only.

### 4.4 Post-Registration Dormancy (FR-4)

On success the wizard:
1. Calls `systemctl stop hostapd` and `systemctl disable hostapd`.
2. Calls `systemctl stop schoolair-wizard` (self-stop).

On the next boot, `launcher.sh` finds `status.json`, exits immediately,
and neither service consumes CPU/RAM.

---

## 5. Functional Requirements

| ID | Requirement | Implementation |
|----|-------------|----------------|
| FR-1 | mDNS as `schoolair-register.local` | Avahi — see `CAPTIVE_PORTAL_SETUP.md` |
| FR-2 | Indoor/Outdoor saved to `status.json` | `environment` field in heartbeat payload + status file |
| FR-3 | WPA Personal (PSK) only | `wifi-sec.key-mgmt wpa-psk` hardcoded in `wizard.py` |
| FR-4 | Post-registration dormancy | hostapd disabled + wizard self-stops on success |

---

## 6. File Manifest

```
registration_wizard/
├── wizard.py                    # Microdot application (main entry point)
├── config.py                    # Deployment-specific constants
├── launcher.sh                  # Boot launcher script
├── setup.sh                     # Automated deployment (runs the checklist below)
├── schoolair-launcher.service   # Systemd unit for launcher
├── schoolair-wizard.service     # Systemd unit for wizard (started on demand)
├── requirements.txt             # Python dependencies
├── CAPTIVE_PORTAL_SETUP.md      # Infrastructure reference (NM hotspot, Avahi, alt. hostapd)
└── PRD_v2.2.md                  # This document
```

---

## 7. Deployment Checklist

### Automated (recommended)

Copy the `registration_wizard/` directory to the Pi, then:

```bash
sudo bash /path/to/registration_wizard/setup.sh
sudo reboot
```

`setup.sh` performs every step below automatically and prints a verification
summary before exiting.

### Manual steps (reference)

- [ ] `pip3 install -r requirements.txt`
- [ ] Copy directory to `/home/admin/registration_wizard/`
- [ ] `chmod +x launcher.sh`
- [ ] Create NM hotspot: `nmcli con add type wifi ifname wlan0 con-name SchoolAir_AP wifi.mode ap ssid SchoolAir_Setup ipv4.method shared ipv4.addresses 192.168.4.1/24 connection.autoconnect no`
- [ ] Write captive-portal dnsmasq config to `/etc/NetworkManager/dnsmasq-shared.d/schoolair-captive.conf`
- [ ] Configure Avahi — see `CAPTIVE_PORTAL_SETUP.md §3`
- [ ] *(Bullseye only)* Add `denyinterfaces wlan0` to `/etc/dhcpcd.conf`
- [ ] `cp schoolair-{launcher,wizard}.service /etc/systemd/system/`
- [ ] `systemctl daemon-reload && systemctl enable schoolair-launcher.service`
- [ ] `systemctl enable schoolair-launcher.service`
- [ ] Reboot and verify with `journalctl -u schoolair-launcher`
