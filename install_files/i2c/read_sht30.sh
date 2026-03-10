#!/bin/bash

# SHT30 (0x44) - Command 0x2C06 (High repeatability, clock stretching disabled)
# 1. Send measurement command
sudo i2ctransfer -y 1 w2@0x44 0x2C 0x06
sleep 0.05 # SHT30 needs ~20-50ms

# 2. Read 6 bytes
DATA=$(sudo i2ctransfer -y 1 r6@0x44 2>&1)
if [ $? -ne 0 ]; then
    echo '{"success": false, "error": "I2C Read Failed"}'
    exit 1
fi

bytes=($DATA)
temp_raw=$(( (bytes[0] << 8) | bytes[1] ))
hum_raw=$(( (bytes[3] << 8) | bytes[4] ))

# Math (SHT30 formulas)
temp_c=$(awk "BEGIN {printf \"%.2f\", -45 + 175 * ($temp_raw / 65535.0)}")
humidity=$(awk "BEGIN {printf \"%.2f\", 100 * ($hum_raw / 65535.0)}")

cat <<EOF
{
  "success": true,
  "data": {
    "temperature_celsius": $temp_c,
    "humidity_percent": $humidity
  }
}
EOF
