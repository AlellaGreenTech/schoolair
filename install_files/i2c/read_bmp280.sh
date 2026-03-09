#!/bin/bash

# BMP280 I2C Address
ADDR=0x76

# 1. Read Calibration Data (0x88 to 0xA1) - 26 bytes
# We use r26 to get all coefficients at once
CAL=$(sudo i2ctransfer -y 1 w1@$ADDR 0x88 r26 2>&1)
if [ $? -ne 0 ]; then
    echo "{\"success\": false, \"error\": \"I2C Read Error: $CAL\"}"
    exit 1
fi
c=($CAL)

# Helper for unsigned 16-bit
get_u16() { echo $(( ($2 << 8) | $1 )); }
# Helper for signed 16-bit
get_s16() {
    local val=$(( ($2 << 8) | $1 ))
    [[ $val -gt 32767 ]] && echo $((val - 65536)) || echo $val
}

# Temperature Calib
T1=$(get_u16 ${c[0]} ${c[1]})
T2=$(get_s16 ${c[2]} ${c[3]})
T3=$(get_s16 ${c[4]} ${c[5]})
# Pressure Calib
P1=$(get_u16 ${c[6]} ${c[7]})
P2=$(get_s16 ${c[8]} ${c[9]})
P3=$(get_s16 ${c[10]} ${c[11]})
P4=$(get_s16 ${c[12]} ${c[13]})
P5=$(get_s16 ${c[14]} ${c[15]})
P6=$(get_s16 ${c[16]} ${c[17]})
P7=$(get_s16 ${c[18]} ${c[19]})
P8=$(get_s16 ${c[20]} ${c[21]})
P9=$(get_s16 ${c[22]} ${c[23]})

# 2. Trigger Measurement (Normal Mode, x1 Oversampling)
sudo i2cset -y 1 $ADDR 0xF4 0x27
sleep 0.1

# 3. Read Raw Data (0xF7 to 0xFC) - 6 bytes
RAW=$(sudo i2ctransfer -y 1 w1@$ADDR 0xF7 r6)
r=($RAW)

# Extract 20-bit Raw Values
adc_p=$(( (${r[0]} << 12) | (${r[1]} << 4) | (${r[2]} >> 4) ))
adc_t=$(( (${r[3]} << 12) | (${r[4]} << 4) | (${r[5]} >> 4) ))

# 4. Compensation Calculations (Math via awk for floating point)
RESULT=$(awk -v T1=$T1 -v T2=$T2 -v T3=$T3 -v P1=$P1 -v P2=$P2 -v P3=$P3 -v P4=$P4 -v P5=$P5 -v P6=$P6 -v P7=$P7 -v P8=$P8 -v P9=$P9 -v adc_t=$adc_t -v adc_p=$adc_p 'BEGIN {
    # Temp Calculation
    var1 = (adc_t / 16384.0 - T1 / 1024.0) * T2
    var2 = ((adc_t / 131072.0 - T1 / 8192.0) * (adc_t / 131072.0 - T1 / 8192.0)) * T3
    t_fine = var1 + var2
    temp = t_fine / 5120.0

    # Pressure Calculation
    v1 = (t_fine / 2.0) - 64000.0
    v2 = v1 * v1 * P6 / 32768.0
    v2 = v2 + v1 * P5 * 2.0
    v2 = (v2 / 4.0) + (P4 * 65536.0)
    v1 = (P3 * v1 * v1 / 524288.0 + P2 * v1) / 524288.0
    v1 = (1.0 + v1 / 32768.0) * P1

    if (v1 == 0) {
        pres = 0
    } else {
        pres = 1048576.0 - adc_p
        pres = (pres - (v2 / 4096.0)) * 6250.0 / v1
        v1 = P9 * pres * pres / 2147483648.0
        v2 = pres * P8 / 32768.0
        pres = pres + (v1 + v2 + P7) / 16.0
    }
    
    printf "%.2f|%.2f", temp, pres/100.0
}')

IFS='|' read -r final_t final_p <<< "$RESULT"

# 5. Output JSON
cat <<EOF
{
  "success": true,
  "sensor": "BMP280",
  "data": {
    "temperature_celsius": $final_t,
    "pressure_hpa": $final_p
  }
}
EOF
