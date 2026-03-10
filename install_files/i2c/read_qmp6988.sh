#!/bin/bash

ADDR=0x70

# 1. Helper functions for Two's Complement conversion
sign16() {
    local v=$1
    if ((v>=32768)); then echo $((v-65536)); else echo $v; fi
}

sign20() {
    local v=$1
    if ((v>=524288)); then echo $((v-1048576)); else echo $v; fi
}

sign24() {
    local v=$1
    if ((v>=8388608)); then echo $((v-16777216)); else echo $v; fi
}

# 2. Read Calibration Data
c=($(i2ctransfer -y 1 w1@$ADDR 0xA1 r25))
if [ ${#c[@]} -lt 25 ]; then
    echo '{"success": false, "error": "I2C calibration read failed"}'
    exit 1
fi

# 3. Trigger Measurement and Read Raw Data
i2cset -y 1 $ADDR 0xF4 0x25
sleep 0.05
r=($(i2ctransfer -y 1 w1@$ADDR 0xF7 r6))

# 4. Map Coefficients (Corrected Register Mapping)
b00=$(sign20 $(( (c[0]<<12) | (c[1]<<4) | (c[2]>>4) )))
bt1=$(sign16 $(( (c[3]<<8) | c[4] )))
bt2=$(sign16 $(( (c[5]<<8) | c[6] )))
bp1=$(sign24 $(( (c[7]<<16) | (c[8]<<8) | c[9] )))
b11=$(sign16 $(( (c[10]<<8) | c[11] )))
b12=$(sign16 $(( (c[12]<<8) | c[13] )))
b21=$(sign16 $(( (c[14]<<8) | c[15] )))
bp2=$(sign16 $(( (c[16]<<8) | c[17] )))
a0=$(sign20 $(( (c[18]<<12) | (c[19]<<4) | (c[20]>>4) )))
a1=$(sign16 $(( (c[21]<<8) | c[22] )))
a2=$(sign16 $(( (c[23]<<8) | c[24] )))

# 5. Raw Values & Crucial Offset Conversion
# We subtract 8388608 (2^23) to center the raw value for the polynomial
raw_p=$(( (r[0]<<16) | (r[1]<<8) | r[2] ))
raw_t=$(( (r[3]<<16) | (r[4]<<8) | r[5] ))

dt=$(echo "$raw_t - 8388608" | bc)
dp=$(echo "$raw_p - 8388608" | bc)

# 6. Compensation Math via bc
# Temperature (Celsius)
temp=$(echo "scale=6; ($a0 + ($a1 * $dt / 1024) + ($a2 * $dt * $dt / 1048576)) / 256" | bc -l)

# Pressure (hPa)
press=$(bc -l <<EOF
scale=6
($b00 + ($bt1 * $dt / 1024) + ($bt2 * $dt * $dt / 1048576) + \
($bp1 * $dp / 1024) + ($b11 * $dp * $dt / 1048576) + \
($b12 * $dp * $dt * $dt / 1073741824) + \
($b21 * $dp * $dp / 1048576) + \
($bp2 * $dp * $dp * $dp / 1073741824)) / 100
EOF
)

# 7. Final JSON Output
printf '{ "success": true, "data": { "temperature_celsius": %.2f, "pressure_hpa": %.2f } }\n' \
"$temp" "$press"
