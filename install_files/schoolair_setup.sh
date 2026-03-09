#!/bin/bash

# --- 1. Variables ---
REPO_URL="https://github.com/yourusername/schoolair-scripts.git"
echo "Step 1: Installing dependencies..."
sudo apt update
sudo apt install -y hostapd dnsmasq nmcli git i2c-tools

# --- 2. Hardware Tweak: Conditional Baudrate ---
echo "Step 2: Checking for HM3301 (0x40)..."
sudo raspi-config nonint do_i2c 0 # Enable I2C

if i2cdetect -y 1 | grep -q "40: 40"; then
    echo "HM3301 detected. Setting I2C baudrate to 100kHz."
    # Update /boot/config.txt safely
    sudo sed -i '/dtparam=i2c_arm_baudrate/d' /boot/config.txt
    echo "dtparam=i2c_arm_baudrate=100000" | sudo tee -a /boot/config.txt
else
    echo "HM3301 not found. Standard I2C speed maintained."
fi

# --- 3. Remote Script Deployment ---
echo "Step 3: Pulling sensor scripts from remote repo..."
rm -rf ~/i2c  # Clean start
git clone $REPO_URL ~/i2c
chmod +x ~/i2c/*.sh

# --- 4. Networking Setup (The "Garage-Tower-Setup") ---
# This part stays local as it configures the specific Pi OS files
# [Include the cat <<EOF blocks for /etc/hostapd/hostapd.conf and /etc/dnsmasq.conf here]

# --- 5. Node-RED ---
echo "Step 5: Installing Node-RED..."
bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) --confirm-install --confirm-pi

echo "Setup complete. Reboot to apply changes."
