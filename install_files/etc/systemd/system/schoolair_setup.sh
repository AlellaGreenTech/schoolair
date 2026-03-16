#!/bin/bash

# run this script on a fresh SchoolAir RPiZ with the following command:
# curl -sSL https://raw.githubusercontent.com/AlellaGreenTech/schoolair/main/install_files/schoolair_setup.sh | bash

# --- 1. System Dependencies ---
echo "Step 1: Installing networking, I2C tools, and Git..."
sudo apt update
# --needed/already installed check is native to apt, but we ensure no prompts
sudo apt install -y hostapd dnsmasq git i2c-tools nginx

# --- 2. Download Project Files ---
echo "Step 2: Syncing SchoolAir repository..."
rm -rf /tmp/schoolair
git clone --depth 1 https://github.com/AlellaGreenTech/schoolair.git /tmp/schoolair

# --- 3. Hardware Tweak: Conditional Baudrate ---
echo "Step 3: Configuring I2C..."
sudo raspi-config nonint do_i2c 0 

# Use a 'grep' check to prevent duplicate lines in config.txt
CONFIG_FILE="/boot/config.txt"
BAUD_LINE="dtparam=i2c_arm_baudrate=100000"

if i2cdetect -y 1 | grep -q "40: 40" || i2cdetect -y 1 | grep -q "6b: 6b"; then
    echo "High-precision sensor detected! Ensuring 100kHz baudrate."
    if ! grep -qF "$BAUD_LINE" "$CONFIG_FILE"; then
        # Remove any existing baudrate lines first to keep it clean
        sudo sed -i '/dtparam=i2c_arm_baudrate/d' "$CONFIG_FILE"
        echo "$BAUD_LINE" | sudo tee -a "$CONFIG_FILE"
    fi
fi

# --- 4. Node-RED Installation ---
# The official script handles 'already installed' cases well
echo "Step 4: Ensuring Node-RED is installed..."
curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered | bash -s -- --confirm-install --confirm-pi

# --- 5. Targeted File Deployment ---
echo "Step 5: Deploying project files..."
mkdir -p ~/i2c
# Use -u (update) to only copy newer files
cp -u /tmp/schoolair/install_files/i2c/*.sh ~/i2c/
chmod +x ~/i2c/*.sh

mkdir -p ~/.node-red
# CAUTION: We use -n (no-clobber) for the flows file so we don't wipe student work
cp -n /tmp/schoolair/install_files/.node-red/flows.json ~/.node-red/ 2>/dev/null || true
cp -u /tmp/schoolair/install_files/.node-red/settings.js ~/.node-red/
cp -u /tmp/schoolair/install_files/.node-red/package.json ~/.node-red/

echo "Installing Node-RED dependencies..."
cd ~/.node-red && npm install --no-audit --no-fund

# --- 6. Networking & Hotspot ---
# Teeing the config is fine as it overwrites (doesn't append)
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=wlan0
driver=nl80211
ssid=Garage-Tower-Setup
hw_mode=g
channel=7
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_passphrase=password123
EOF

# Same for the service and script - overwriting is safer than appending
sudo tee /usr/bin/autohotspot.sh > /dev/null <<EOF
#!/bin/bash
sleep 10
if ! ip addr show wlan0 | grep -q "inet "; then
    sudo ifconfig wlan0 192.168.4.1 netmask 255.255.255.0
    sudo systemctl start hostapd
    sudo systemctl start dnsmasq
fi
EOF
sudo chmod +x /usr/bin/autohotspot.sh

sudo tee /etc/systemd/system/autohotspot.service > /dev/null <<EOF
[Unit]
Description=Auto Hotspot if no WiFi
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/autohotspot.sh

[Install]
WantedBy=multi-user.target
EOF

# --- 7. Final Cleanup & Service Start ---
sudo systemctl unmask hostapd 2>/dev/null || true
sudo systemctl enable --now hostapd dnsmasq autohotspot.service

# Nginx Redirect (Overwrites existing default)
sudo tee /etc/nginx/sites-available/default > /dev/null <<EOF
server {
    listen 80;
    server_name _;
    location / {
        return 301 http://\$host:1880/ui;
    }
}
EOF

sudo systemctl enable --now nginx
rm -rf /tmp/schoolair

echo "-------------------------------------------------------"
echo "IDEMPOTENT SETUP COMPLETE."
echo "-------------------------------------------------------"
echo "REBOOT TO START SENSORS AND NETWORKING."
echo "-------------------------------------------------------"
