$ cat i2c/read_sht40.sh 
#!/bin/bash

# Read SHT40 (0x44) - Temperature and Humidity sensor with error handling
# Command 0xFD = High repeatability (wait ~10ms)

# Send measurement command
CMD_OUTPUT=$(sudo i2ctransfer -y 1 w1@0x44 0xFD 2>&1)
CMD_EXIT=$?

if [ $CMD_EXIT -ne 0 ]; then
    cat <<EOF
{
  "success": false,
  "error": "Failed to send measurement command to SHT40: $CMD_OUTPUT",
  "error_type": "SENSOR_COMMAND_ERROR"
}
EOF
    exit 1
fi

# Wait for measurement to complete
sleep 0.01  # 10ms

# Read 6 bytes: Temp_MSB, Temp_LSB, Temp_CRC, Hum_MSB, Hum_LSB, Hum_CRC
DATA=$(sudo i2ctransfer -y 1 r6@0x44 2>&1)
READ_EXIT=$?

if [ $READ_EXIT -ne 0 ]; then
    cat <<EOF
{
  "success": false,
  "error": "Failed to read data from SHT40: $DATA",
  "error_type": "SENSOR_READ_ERROR"
}
EOF
    exit 1
fi

# Parse data into array
bytes=($DATA)

# Check if we got the expected 6 bytes
if [ ${#bytes[@]} -ne 6 ]; then
    cat <<EOF
{
  "success": false,
  "error": "Invalid data length: expected 6 bytes, got ${#bytes[@]}",
  "error_type": "INVALID_DATA_LENGTH"
}
EOF
    exit 1
fi

# Calculate temperature
temp_msb=$((${bytes[0]}))
temp_lsb=$((${bytes[1]}))
temp_raw=$(( (temp_msb << 8) | temp_lsb ))
temp_c=$(awk "BEGIN {printf \"%.2f\", -45 + 175 * ($temp_raw / 65535.0)}")

# Calculate humidity
hum_msb=$((${bytes[3]}))
hum_lsb=$((${bytes[4]}))
hum_raw=$(( (hum_msb << 8) | hum_lsb ))
humidity=$(awk "BEGIN {printf \"%.2f\", -6 + 125 * ($hum_raw / 65535.0)}")

# Clamp humidity between 0-100%
if (( $(awk "BEGIN {print ($humidity < 0)}") )); then
    humidity="0.00"
elif (( $(awk "BEGIN {print ($humidity > 100)}") )); then
    humidity="100.00"
fi

# Validate temperature range (SHT40: -40 to +125°C)
temp_check=$(awk "BEGIN {print ($temp_c < -40 || $temp_c > 125)}")
if [ "$temp_check" = "1" ]; then
    cat <<EOF
{
  "success": false,
  "error": "Temperature out of range: ${temp_c}°C (valid: -40 to 125°C)",
  "error_type": "INVALID_READING"
}
EOF
    exit 1
fi

# Output success JSON
cat <<EOF
{
  "success": true,
  "timestamp": "$(date -Iseconds)",
  "sensor": "SHT40",
  "address": "0x44",
  "data": {
    "temperature_celsius": $temp_c,
    "humidity_percent": $humidity
  }
}
EOF
