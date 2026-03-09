#!/bin/bash

# --- 1. System Dependencies ---
echo "Installing networking and I2C tools..."
sudo apt update
sudo apt install -y hostapd dnsmasq nmcli i2c-tools

# --- 2. Conditional I2C Baudrate Tweak ---
echo "Scanning for HM3301 (0x40)..."
sudo raspi-config nonint do_i2c 0 # Ensure I2C is active

# Check if HM3301 is present before slowing the bus
if i2cdetect -y 1 | grep -q "40: 40"; then
    echo "HM3301 detected! Setting I2C baudrate to 100kHz for stability."
    sudo sed -i '/dtparam=i2c_arm_baudrate/d' /boot/config.txt
    echo "dtparam=i2c_arm_baudrate=100000" | sudo tee -a /boot/config.txt
else
    echo "HM3301 (0x40) not found. Leaving I2C at standard speed."
fi

# --- 3. Deploy Sensor Scripts ---
echo "Deploying I2C scripts to ~/i2c/..."
mkdir -p ~/i2c
cp ./i2c/*.sh ~/i2c/
chmod +x ~/i2c/*.sh

# --- 4. Node-RED Setup ---
echo "Installing Node-RED..."
# Standard Pi installer
bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) --confirm-install --confirm-pi

# Move your pre-configured flows into place
mkdir -p ~/.node-red
cp ./flows.json ~/.node-red/flows.json

# --- 5. Networking (Hotspot Recovery) ---
echo "Configuring Garage-Tower-Setup hotspot..."
# [The script would continue here with the cat <<EOF blocks for hostapd/dnsmasq]

echo "Installation complete. Please reboot."
