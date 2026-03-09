#!/bin/bash

# run this script on a fresh SchoolAir RPiZ with the following command:
# curl -sSL https://raw.githubusercontent.com/AlellaGreenTech/schoolair/main/install_files/schoolair_setup.sh | bash

# --- 1. System Dependencies ---
echo "Step 1: Installing networking, I2C tools, and Git..."
sudo apt update
sudo apt install -y hostapd dnsmasq nmcli git i2c-tools

# --- 2. Download Project Files ---
echo "Step 2: Cloning the SchoolAir repository to /tmp..."
rm -rf /tmp/schoolair
git clone --depth 1 https://github.com/AlellaGreenTech/schoolair.git /tmp/schoolair

# --- 3. Hardware Tweak: Conditional Baudrate ---
echo "Step 3: Scanning I2C bus for HM3301 (0x40)..."
sudo raspi-config nonint do_i2c 0 # Ensure I2C is active

# HM3301 requires 100kHz for stability on the Pi Zero
if i2cdetect -y 1 | grep -q "40: 40"; then
    echo "HM3301 detected! Setting I2C baudrate to 100kHz."
    sudo sed -i '/dtparam=i2c_arm_baudrate/d' /boot/config.txt
    echo "dtparam=i2c_arm_baudrate=100000" | sudo tee -a /boot/config.txt
else
    echo "HM3301 not found. Leaving I2C at standard speed."
fi

# --- 4. Node-RED Installation ---
echo "Step 4: Installing Node-RED (this may take several minutes)..."
# Official installer for Raspberry Pi
bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) --confirm-install --confirm-pi

# --- 5. Targeted File Deployment (Post-Installation) ---
echo "Step 5: Deploying project files..."

# Deploy Shell-based Sensor Scripts
mkdir -p ~/i2c
cp -r /tmp/schoolair/install_files/i2c/*.sh ~/i2c/
chmod +x ~/i2c/*.sh

# Deploy Node-RED Configuration (including settings, flows, and package.json)
mkdir -p ~/.node-red
cp -r /tmp/schoolair/install_files/.node-red/* ~/.node-red/

# Auto-install missing nodes from package.json
echo "Installing Node-RED dependencies from package.json..."
cd ~/.node-red && npm install

# --- 6. Networking & Hotspot Recovery ---
echo "Step 6: Setting up Garage-Tower-Setup Hotspot..."

# hostapd config
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

# Auto-Hotspot Switch Script (Captive Portal gateway)
sudo tee /usr/bin/autohotspot.sh > /dev/null <<EOF
#!/bin/bash
sleep 10
if ! nmcli -t -f TYPE,STATE dev | grep -q "wireless:connected"; then
    sudo ifconfig wlan0 192.168.4.1 netmask 255.255.255.0
    sudo systemctl start hostapd
    sudo systemctl start dnsmasq
fi
EOF
sudo chmod +x /usr/bin/autohotspot.sh

# Systemd Service for boot trigger
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

sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl enable autohotspot.service

# --- 7. Final Cleanup ---
rm -rf /tmp/schoolair
echo "-------------------------------------------------------"
echo "SETUP COMPLETE. SYSTEM IS NOW CONFIGURED FOR SCHOOLAIR."
echo "REBOOT TO START SENSORS AND NETWORKING."
echo "-------------------------------------------------------"
