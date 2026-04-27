# SchoolAir Gatekeeper – deployment configuration
# Edit this file before deploying to each unit.

# AWS heartbeat endpoint
HEARTBEAT_URL = "https://data.schoolair.org/aqc/register"
HEARTBEAT_TIMEOUT = 15  # seconds

# Local storage
CONFIG_DIR       = "/home/admin/.config/schoolair"
STAGING_FILE     = CONFIG_DIR + "/staging.json"
STATUS_FILE      = CONFIG_DIR + "/status.json"
ERROR_FILE       = CONFIG_DIR + "/last_error.txt"

# Networking
AP_INTERFACE          = "wlan0"
# Name of the NetworkManager connection that holds the AP / hotspot profile.
# Check with:  nmcli con show
AP_CONNECTION_NAME     = "SchoolAir_AP"
# Ephemeral client profile created each time the wizard runs.
CLIENT_CONNECTION_NAME = "schoolair-client"

# Web server
SERVER_PORT = 80
