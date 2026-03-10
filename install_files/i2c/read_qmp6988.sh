#!/bin/bash

# QMP6988 I2C Address (M5Stack ENV III default)
ADDR=0x70

# 1. Read Calibration Data (0xA1 to 0xB9) - 25 bytes
CAL=$(sudo i2ctransfer -y 1 w1@$ADDR 0xA1 r25 2>&1)
if [ $? -ne 0 ]; then
    echo "{\"success\": false, \"error\": \"I2C Read Error: $CAL\"}"
    exit 1
fi
c=($CAL)

# Helper to parse signed 16-bit
get_s16() {
    local val=$(( ($1 << 8) | $2 ))
    [[ $val -gt 32767 ]] && echo $((val - 65536)) || echo $val
}

# Helper to parse signed 20-bit (used for b00 and a0)
get_s20() {
    local val=$(( ($1 << 12) | ($2 << 4) | ($3 >> 4) ))
    [[ $val -gt 524287 ]] && echo $((val - 1048576)) || echo $val
}

# Helper to parse signed 24-bit (used for bp1)
get_s24() {
    local val=$(( ($1 << 16) | ($2 << 8) | $3 ))
    [[ $val -gt 8388607 ]] && echo $((val - 16777216)) || echo $val
}

# Mapping Coefficients
b00=$(get_s20 ${c[0]} ${c[1]} ${c[2]})
bt1=$(get_s16 ${c[3]} ${c[4]})
bt2=$(get_s16 ${c[5]} ${c[6]})
bp1=$(get_s24 ${c[7]} ${c[8]} ${c[9]})
b11=$(get_s16 ${c[10]} ${c[11]})
b12=$(get_s16 ${c[12]} ${c[13]})
b21=$(get_s16 ${c[14]} ${c[15]})
bp2=$(get_s16 ${c[16]} ${c[17]})
a0=$(get_s20 ${c[18]} ${c[19]} ${c[20]})
a1=$(get_s16 ${c[21]} ${c[22]})
a2=$(get_s16 ${c[23]} ${c[24]})

# 2. Trigger Measurement (Forced Mode, OSS 1x for T and P)
# 0x25 = 001 (Temp 1x) 001 (Press 1x) 01 (Forced)
sudo i2cset -y 1 $ADDR 0xF4 0x25
sleep 0.05

# 3. Read Raw Data (0xF7 to 0xFC) - 6 bytes
RAW=$(sudo i2ctransfer -y 1 w1@$ADDR 0xF7 r6)
r=($RAW)

# Extract 24-bit Raw Values
raw_p=$(( (${r[0]} << 16) | (${r[1]} << 8) | ${r[2]} ))
raw_t=$(( (${r[3]} << 16) | (${r[4]} << 8) | ${r[5]} ))

# 4. Compensation Calculations via awk
RESULT=$(awk -v b00=$b00 -v bt1=$bt1 -v bt2=$bt2 -v bp1=$bp1 -v b11=$b11 -v b12=$b12 -v b21=$b21 -v bp2=$bp2 -v a0=$a0 -v a1=$a1 -v a2=$a2 -v raw_p=$raw_p -v raw_t=$raw_t 'BEGIN {
    # Constants from datasheet
    dt = raw_t - 8388608.0
    dp = raw_p - 8388608.0
    
    # Temperature Calculation (Result is in Celsius * 256)
    temp_c = (a0 + (a1 * dt) + (a2 * dt * dt)) / 256.0
    
    # Pressure Calculation (Result is in Pascals)
    press_pa = b00 + (bt1 * dt) + (bt2 * dt * dt) + (bp1 * dp) + (b11 * dp * dt) + (b12 * dp * dt * dt) + (b21 * dp * dp) + (bp2 * dp * dp * dp)
    
    printf "%.2f|%.2f", temp_c, press_pa / 100.0
}')

# 5. Output JSON
TEMP=$(echo $RESULT | cut -d'|' -f1)
PRESS=$(echo $RESULT | cut -d'|' -f2)

cat <<EOF
{
  "success": true,
  "sensor": "QMP6988",
  "data": {
    "temperature_celsius": $TEMP,
    "pressure_hpa": $PRESS
  }
}
EOF
