$ cat read_hm3301.sh
#!/bin/bash

# 1. Read the 29-byte data packet using the modern 'transfer' method
# We write 0x88 (the read command) and immediately read 29 bytes
DATA=$(i2ctransfer -y 1 r29@0x40 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "{\"success\": false, \"error\": \"I2C Read Failed: $DATA\"}"
    exit 1
fi

# Convert hex output (0xAA 0xBB...) into an array
bytes=($DATA)

# 2. Checksum Verification
sum=0
for i in {0..27}; do
    val=$((bytes[i]))
    sum=$((sum + val))
done
checksum_calc=$((sum & 0xFF))
checksum_sent=$((bytes[28]))

if [ $checksum_calc -ne $checksum_sent ]; then
    echo "{\"success\": false, \"error\": \"Checksum mismatch\"}"
    exit 1
fi

# 3. Extraction Helper
get_value() {
    local msb=$((bytes[$1]))
    local lsb=$((bytes[$1+1]))
    echo $(( (msb << 8) + lsb ))
}

# 4. Output Clean JSON
# Mapping based on Seeed HM3301 Datasheet
cat <<EOF
{
  "success": true,
  "data": {
    "pm1_0_std": $(get_value 4),
    "pm2_5_std": $(get_value 6),
    "pm10_std": $(get_value 8),
    "pm1_0_atm": $(get_value 10),
    "pm2_5_atm": $(get_value 12),
    "pm10_atm": $(get_value 14)
  }
}
EOF
