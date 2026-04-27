#!/usr/bin/env python3
"""
SchoolAir Gatekeeper Registration Wizard
Microdot captive-portal that registers the device with the SchoolAir Cloud.

Run order:
  launcher.sh  →  this process  →  background registration task  →  self-stop
"""

import asyncio
import html as _html
import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

from microdot import Microdot, Response

from config import (
    AP_CONNECTION_NAME,
    AP_INTERFACE,
    CLIENT_CONNECTION_NAME,
    CONFIG_DIR,
    ERROR_FILE,
    HEARTBEAT_TIMEOUT,
    HEARTBEAT_URL,
    SERVER_PORT,
    STAGING_FILE,
    STATUS_FILE,
)

app = Microdot()

# Single shared state dict — all mutations happen inside the asyncio event loop,
# so no locks are needed.
reg_state: dict = {"state": "idle", "message": ""}


# ── HTML helpers ──────────────────────────────────────────────────────────────

def _render(template: str, raw: dict = None, **kwargs) -> str:
    """Replace [[key]] placeholders.
    kwargs values are HTML-escaped; raw values are inserted verbatim."""
    for k, v in kwargs.items():
        template = template.replace(f"[[{k}]]", _html.escape(str(v)))
    for k, v in (raw or {}).items():
        template = template.replace(f"[[{k}]]", str(v))
    return template


def _html_response(body: str, status: int = 200) -> Response:
    return Response(body, status_code=status,
                    headers={"Content-Type": "text/html; charset=utf-8"})


# ── FORM page ─────────────────────────────────────────────────────────────────

FORM_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SchoolAir Setup</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
     background:#f0f4f8;min-height:100vh;display:flex;
     align-items:center;justify-content:center;padding:1rem}
.card{background:#fff;border-radius:16px;padding:2rem;max-width:420px;
      width:100%;box-shadow:0 4px 24px rgba(0,0,0,.1)}
.logo{text-align:center;margin-bottom:1.5rem}
.logo h1{font-size:1.5rem;color:#1a56db;font-weight:700}
.logo p{color:#6b7280;font-size:.875rem;margin-top:.25rem}
.sect{font-size:.72rem;font-weight:600;color:#6b7280;text-transform:uppercase;
      letter-spacing:.05em;margin:1.25rem 0 .4rem}
label{display:block;font-size:.875rem;font-weight:500;color:#374151;
      margin-bottom:.2rem;margin-top:.65rem}
input[type=text],input[type=password]{width:100%;padding:.6rem .75rem;
  border:1.5px solid #d1d5db;border-radius:8px;font-size:1rem;outline:none;
  transition:border-color .2s}
input:focus{border-color:#1a56db}
.tog{display:flex;gap:.5rem;margin-top:.5rem}
.tog input[type=radio]{display:none}
.tog label{flex:1;text-align:center;padding:.6rem;border:1.5px solid #d1d5db;
  border-radius:8px;cursor:pointer;font-weight:500;color:#6b7280;
  transition:all .2s;margin:0}
.tog input[type=radio]:checked+label{background:#1a56db;color:#fff;border-color:#1a56db}
.pw{position:relative}
.pw input{padding-right:3rem}
.pw button{position:absolute;right:.75rem;top:50%;transform:translateY(-50%);
  background:none;border:none;cursor:pointer;color:#6b7280;font-size:.85rem}
.err{background:#fef2f2;color:#dc2626;padding:.75rem;border-radius:8px;
     font-size:.875rem;margin-top:.75rem}
.btn{width:100%;margin-top:1.5rem;padding:.875rem;background:#1a56db;
     color:#fff;border:none;border-radius:10px;font-size:1rem;font-weight:600;
     cursor:pointer;transition:background .2s}
.btn:hover{background:#1649c0}
</style>
</head>
<body>
<div class="card">
  <div class="logo"><h1>SchoolAir Setup</h1><p>Register this monitoring device</p></div>
  [[error_block]]
  <form method="POST" action="/register">
    <div class="sect">Identity</div>
    <label for="token">Registration Token</label>
    <input type="text" id="token" name="token" required
           placeholder="e.g. SA-2024-XXXXX" value="[[token]]">
    <label for="site">Site Name</label>
    <input type="text" id="site" name="site" required
           placeholder="e.g. Lincoln Elementary" value="[[site]]">
    <label for="asset_name">Asset Name</label>
    <input type="text" id="asset_name" name="asset_name" required
           placeholder="e.g. Room 302" value="[[asset_name]]">

    <div class="sect">Environment</div>
    <div class="tog">
      <input type="radio" id="ev_in" name="environment" value="indoor" [[indoor_checked]]>
      <label for="ev_in">Indoor</label>
      <input type="radio" id="ev_out" name="environment" value="outdoor" [[outdoor_checked]]>
      <label for="ev_out">Outdoor</label>
    </div>

    <div class="sect">Network</div>
    <label for="ssid">Wi-Fi Network (SSID)</label>
    <input type="text" id="ssid" name="ssid" required
           placeholder="School Wi-Fi name" value="[[ssid]]">
    <label for="password">Wi-Fi Password</label>
    <div class="pw">
      <input type="password" id="password" name="password" required
             placeholder="WPA Personal password">
      <button type="button" onclick="tpw()">Show</button>
    </div>
    <button type="submit" class="btn">Register &amp; Connect</button>
  </form>
</div>
<script>
function tpw(){const f=document.getElementById('password'),b=f.nextElementSibling;
  if(f.type==='password'){f.type='text';b.textContent='Hide';}
  else{f.type='password';b.textContent='Show';}}
</script>
</body></html>"""


# ── CONNECTING page ───────────────────────────────────────────────────────────

CONNECTING_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SchoolAir – Connecting</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
     background:#f0f4f8;min-height:100vh;display:flex;
     align-items:center;justify-content:center;padding:1rem}
.card{background:#fff;border-radius:16px;padding:2rem 1.5rem;max-width:420px;
      width:100%;text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.1)}
h1{font-size:1.4rem;color:#1a56db;margin-bottom:.5rem}
#icon{font-size:3rem;margin:1.5rem 0}
#msg{color:#374151;font-size:1rem;min-height:3rem;line-height:1.5}
#hint{color:#6b7280;font-size:.8rem;margin-top:1rem;padding:.75rem;
      background:#f9fafb;border-radius:8px;display:none;line-height:1.5}
.spin{display:inline-block;width:2.5rem;height:2.5rem;
      border:4px solid #e5e7eb;border-top-color:#1a56db;
      border-radius:50%;animation:sp .8s linear infinite}
@keyframes sp{to{transform:rotate(360deg)}}
#retry{display:none;margin-top:1.5rem;padding:.75rem 1.5rem;
       background:#1a56db;color:#fff;border:none;border-radius:8px;
       font-size:1rem;cursor:pointer}
</style>
</head>
<body>
<div class="card">
  <h1>SchoolAir Setup</h1>
  <div id="icon"><div class="spin"></div></div>
  <div id="msg">Connecting to network&hellip;</div>
  <div id="hint"></div>
  <button id="retry" onclick="location.href='/'">Try Again</button>
</div>
<script>
const AP_DROP = "The setup hotspot dropped — the device is connecting to the school Wi-Fi. " +
  "If successful, registration is complete. If the hotspot reappears within 60 seconds, " +
  "tap Try Again to review the error.";

function icon(t){
  const el=document.getElementById('icon');
  if(t==='spin') el.innerHTML='<div class="spin"></div>';
  else el.textContent=t;
}
function hint(t){const h=document.getElementById('hint');h.textContent=t;h.style.display='block';}
function msg(t){document.getElementById('msg').textContent=t;}

let ws, dropped=false, reconnTimer;

function connect(){
  const proto = location.protocol==='https:'?'wss':'ws';
  ws=new WebSocket(proto+'://'+location.host+'/ws/status');
  ws.onmessage=function(e){
    const d=JSON.parse(e.data);
    if(d.state==='ping') return;
    msg(d.message);
    if(d.state==='success'){
      icon('✅');
      hint('Registration complete. This hotspot will close shortly.');
    } else if(d.state==='error'){
      icon('❌');
      document.getElementById('retry').style.display='inline-block';
    }
  };
  ws.onclose=function(){
    clearTimeout(reconnTimer);
    if(!dropped){
      dropped=true;
      icon('📶');
      msg(AP_DROP);
      hint('On Pi Zero hardware the setup hotspot may drop during connection — this is normal.');
    }
    // Attempt reconnect in case AP comes back (failure path)
    reconnTimer=setTimeout(connect, 3000);
  };
  ws.onerror=function(){ws.close();};
}
connect();
</script>
</body></html>"""


# ── Persistence helpers ───────────────────────────────────────────────────────

def _ensure_dir() -> None:
    os.makedirs(CONFIG_DIR, exist_ok=True)


def write_staging(data: dict) -> None:
    _ensure_dir()
    tmp = STAGING_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, STAGING_FILE)


def read_staging() -> dict:
    try:
        with open(STAGING_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def write_status(data: dict) -> None:
    _ensure_dir()
    tmp = STATUS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, STATUS_FILE)


def write_error(message: str) -> None:
    _ensure_dir()
    with open(ERROR_FILE, "w") as f:
        f.write(f"{datetime.now(timezone.utc).isoformat()}  {message}\n")


def status_exists() -> bool:
    return os.path.exists(STATUS_FILE)


# ── Async shell helpers ───────────────────────────────────────────────────────

async def _cmd(cmd: str) -> tuple:
    """Run a shell command; return (returncode, stdout, stderr)."""
    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    out, err = await proc.communicate()
    return proc.returncode, out.decode().strip(), err.decode().strip()


# ── Network operations ────────────────────────────────────────────────────────

async def _setup_client_profile(ssid: str, password: str) -> tuple:
    """Create (or replace) the NM client Wi-Fi connection profile."""
    await _cmd(f'nmcli con delete "{CLIENT_CONNECTION_NAME}" 2>/dev/null; true')
    rc, _, err = await _cmd(
        f'nmcli con add type wifi ifname {AP_INTERFACE} '
        f'con-name "{CLIENT_CONNECTION_NAME}" '
        f'ssid "{ssid}" '
        f'wifi-sec.key-mgmt wpa-psk '
        f'wifi-sec.psk "{password}" '
        f'ipv4.method auto '
        f'ipv6.method ignore'
    )
    if rc != 0:
        return False, f"Could not create connection profile: {err}"
    return True, "ok"


async def _wait_for_ip(timeout: int = 30) -> bool:
    """Poll until the interface has been assigned an IPv4 address."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        rc, out, _ = await _cmd(
            f"nmcli -t -f IP4.ADDRESS dev show {AP_INTERFACE}"
        )
        if rc == 0 and out.strip():
            return True
        await asyncio.sleep(2)
    return False


async def _revert_to_ap() -> None:
    """Drop the client connection and restore the AP."""
    await _cmd(f'nmcli con down "{CLIENT_CONNECTION_NAME}" 2>/dev/null; true')
    rc, _, _ = await _cmd(f'nmcli con up "{AP_CONNECTION_NAME}" 2>/dev/null')
    if rc != 0:
        # Hard fallback: hostapd may be managing the AP directly.
        await _cmd("systemctl restart hostapd 2>/dev/null; true")


async def _post_heartbeat(payload: dict) -> tuple:
    """POST registration payload to SchoolAir Cloud. Returns (success, message)."""
    body = json.dumps(payload).encode()

    def _do() -> tuple:
        req = urllib.request.Request(
            HEARTBEAT_URL,
            data=body,
            headers={
                "Content-Type": "application/json",
                "Accept":       "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=HEARTBEAT_TIMEOUT) as r:
            return r.status, r.read().decode()

    loop = asyncio.get_running_loop()
    try:
        code, _ = await loop.run_in_executor(None, _do)
        if code == 200:
            return True, "Registered successfully"
        return False, f"Server returned HTTP {code}"
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            return False, "Token rejected by SchoolAir Cloud"
        return False, f"Server error HTTP {exc.code}"
    except urllib.error.URLError as exc:
        return False, f"Could not reach SchoolAir Cloud: {exc.reason}"
    except Exception as exc:  # noqa: BLE001
        return False, f"Heartbeat failed: {exc}"


# ── Registration background task ──────────────────────────────────────────────

def _set(state: str, message: str) -> None:
    reg_state["state"] = state
    reg_state["message"] = message


async def run_registration(data: dict) -> None:
    """
    Full registration sequence.  Runs as an asyncio background task.

    On Pi Zero v1 (no concurrent AP+Station), the AP will drop when nmcli
    brings up the client connection.  The browser's WebSocket will close and
    show the fallback message.  If we fail and restore the AP, the browser
    will reconnect and display the error automatically.
    """
    ssid = data["ssid"]
    password = data["password"]

    # 1. Create NM profile
    _set("connecting", f"Adding connection profile for \"{ssid}\"…")
    ok, msg = await _setup_client_profile(ssid, password)
    if not ok:
        _set("error", msg)
        write_error(msg)
        await _revert_to_ap()
        return

    # 2. Bring up client connection (AP may drop here on Pi Zero v1)
    _set("connecting", f"Connecting to \"{ssid}\"…")
    rc, _, err = await _cmd(f'nmcli con up "{CLIENT_CONNECTION_NAME}"')
    if rc != 0:
        detail = err or "Check SSID and password."
        msg = f"Could not connect to \"{ssid}\": {detail}"
        _set("error", msg)
        write_error(msg)
        await _revert_to_ap()
        return

    # 3. Wait for IP address
    _set("wifi_up", f"Joined \"{ssid}\". Waiting for IP address…")
    got_ip = await _wait_for_ip(timeout=30)
    if not got_ip:
        msg = f"Joined \"{ssid}\" but did not receive an IP address within 30 s."
        _set("error", msg)
        write_error(msg)
        await _revert_to_ap()
        return

    # 4. Heartbeat to AWS
    _set("heartbeat", "On the school network. Sending registration to SchoolAir Cloud…")
    payload = {
        "token":        data["token"],
        "site":         data["site"],
        "asset_name":   data["asset_name"],
        "environment":  data["environment"],
        "ssid":         ssid,
        "registered_at": datetime.now(timezone.utc).isoformat(),
    }
    success, hb_msg = await _post_heartbeat(payload)

    if success:
        write_status(payload)
        try:
            os.remove(STAGING_FILE)
        except FileNotFoundError:
            pass
        _set("success", "Registration complete! This hotspot will shut down shortly.")
        asyncio.create_task(_delayed_shutdown())
    else:
        _set("error", f"Wi-Fi connected, but: {hb_msg}")
        write_error(hb_msg)
        await _revert_to_ap()


async def _delayed_shutdown() -> None:
    """Give the browser time to receive the success message, then shut down."""
    await asyncio.sleep(6)
    await _cmd(f'nmcli con down "{AP_CONNECTION_NAME}" 2>/dev/null; true')
    await _cmd("systemctl stop hostapd 2>/dev/null; true")
    await _cmd("systemctl disable hostapd 2>/dev/null; true")
    await _cmd("systemctl stop schoolair-wizard 2>/dev/null; true")


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/", methods=["GET"])
async def index(request):
    prefill = read_staging()
    env = prefill.get("environment", "")
    error_block = ""
    if reg_state["state"] == "error":
        error_block = (
            f'<div class="err">{_html.escape(reg_state["message"])}</div>'
        )
    body = _render(
        FORM_HTML,
        raw={"error_block": error_block,
             "indoor_checked": "checked" if env == "indoor" else "",
             "outdoor_checked": "checked" if env == "outdoor" else ""},
        token=prefill.get("token", ""),
        site=prefill.get("site", ""),
        asset_name=prefill.get("asset_name", ""),
        ssid=prefill.get("ssid", ""),
    )
    return _html_response(body)


@app.route("/register", methods=["POST"])
async def register(request):
    f = request.form
    data = {
        "token":       f.get("token", "").strip(),
        "site":        f.get("site", "").strip(),
        "asset_name":  f.get("asset_name", "").strip(),
        "environment": f.get("environment", "indoor").strip(),
        "ssid":        f.get("ssid", "").strip(),
        "password":    f.get("password", "").strip(),
    }
    if not all(data.values()):
        env = data.get("environment", "")
        body = _render(
            FORM_HTML,
            raw={
                "error_block": '<div class="err">Please fill in all fields.</div>',
                "indoor_checked": "checked" if env == "indoor" else "",
                "outdoor_checked": "checked" if env == "outdoor" else "",
            },
            token=data["token"],
            site=data["site"],
            asset_name=data["asset_name"],
            ssid=data["ssid"],
        )
        return _html_response(body, status=422)

    _set("connecting", "Starting registration…")
    write_staging(data)
    asyncio.create_task(run_registration(data))
    return _html_response(CONNECTING_HTML)


@app.websocket("/ws/status")
async def ws_status(request, ws):
    last = {}
    while True:
        current = dict(reg_state)
        if current != last:
            await ws.send(json.dumps(current))
            last = dict(current)
            if current["state"] in ("success", "error"):
                await asyncio.sleep(1)
                break
        await asyncio.sleep(0.4)


@app.route("/status.json", methods=["GET"])
async def status_endpoint(request):
    """Lightweight JSON status — useful for debugging from curl."""
    return Response(
        json.dumps(reg_state),
        headers={"Content-Type": "application/json"},
    )


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if status_exists():
        print("[schoolair-wizard] status.json exists — device already registered. Exiting.")
        raise SystemExit(0)
    print(f"[schoolair-wizard] Starting on port {SERVER_PORT}")
    app.run(host="0.0.0.0", port=SERVER_PORT, debug=False)
