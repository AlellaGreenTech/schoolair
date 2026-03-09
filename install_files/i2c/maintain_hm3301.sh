#!/bin/bash

# I2C Address for HM3301
ADDR=0x40

# Commands based on Seeed protocol
START_FAN="0x88 0x01" # Select Active Mode
STOP_FAN="0x88 0x00"  # Select Standby Mode (Stops fan)

echo "--- STARTING HM3301 PURGE CYCLE ---"

# Phase 1: Rapid Tossing (10 cycles)
for i in {1..10}
do
    echo "Pulse $i: Tossing..."
    sudo i2cset -y 1 $ADDR $START_FAN
    sleep 1
    sudo i2cset -y 1 $ADDR $STOP_FAN
    sleep 0.5
done

# Phase 2: High-Speed Flush
echo "Phase 2: High-speed flush for 30 seconds..."
sudo i2cset -y 1 $ADDR $START_FAN
sleep 30

# Phase 3: Final Reading
echo "Phase 3: Taking stabilized reading..."
# We wait 5 seconds for the laser to stabilize after the high-speed flush
sleep 5

DATA=$(sudo i2ctransfer -y 1 w1@$ADDR 0x88 r29)
bytes=($DATA)

# HM3301 PM2.5 Standard is at bytes 8 and 9 (index starts at 0)
msb=${bytes[8]}
lsb=${bytes[9]}
pm25=$(( (msb << 8) + lsb ))

echo "--- PURGE COMPLETE ---"
echo "Final PM2.5 Reading: $pm25 μg/m³"

if [ $pm25 -lt 10 ]; then
    echo "SUCCESS: Noise floor significantly reduced."
else
    echo "RESULT: Noise floor remains at $pm25 μg/m³. The 'dust' may be internal lens degradation or humidity."
fi
