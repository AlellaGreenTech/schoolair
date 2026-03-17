#!/bin/bash
# SchoolAir Golden Image Preparation Script - V1.2

echo "--- Starting Professional Cleanup ---"

# 0. Remove SchoolAir Tokens
rm ~/.device_token

# 1. Stop all production services
sudo systemctl stop node-red
sudo systemctl stop sen6x.service
sudo systemctl stop schoolair-init.service

# 2. Node-RED Specific Cleanup
echo "Cleaning Node-RED backups..."
# Removes local context and backup flows so the image starts fresh
rm -f /home/$(whoami)/.node-red/.config.json.backup
rm -f /home/$(whoami)/.node-red/flows_*.json.backup

# 3. APT Package Cleanup
echo "Cleaning APT cache..."
sudo apt-get autoremove -y
sudo apt-get clean

# 4. Reset Identity & Cloud-Init
echo "Resetting Cloud-Init..."
sudo cloud-init clean --logs
sudo rm -rf /var/lib/cloud/instances/*
sudo rm -f /var/lib/schoolair_initialized

# 5. Reset Hostname to Template
echo "Resetting Hostname..."
sudo hostnamectl set-hostname schoolair-template
echo "schoolair-template" | sudo tee /etc/hostname
sudo sed -i "s/^127.0.1.1.*/127.0.1.1\tschoolair-template/g" /etc/hosts

# 6. Clear Logs and History
echo "Final log wipe..."
sudo find /var/log -type f -exec sudo truncate -s 0 {} \;
cat /dev/null > ~/.bash_history && history -c

# 7. Prime for First Boot
sudo systemctl enable schoolair-init.service

echo "--- READY. Shut down your device when you're ready. ---"
# 5. Clear unique SSH Host Keys (The init script will regenerate them)
#echo "Removing SSH host keys..."
#sudo rm -f /etc/ssh/ssh_host_*
