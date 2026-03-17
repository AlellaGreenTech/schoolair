#!/usr/bin/python3
'''
 * LIBRARIES *
'''
# General Purpose
import math
import time
import json
import board # I2C
import busio # I2C
# Grove - Gas Sensor V2 (Multichannel)
from AndresMercado.multichannel_gas_gmxxx import MultichannelGasGMXXX

'''
 *  INIT COMMUNICATIONS  *
'''
# Initialize I2C
i2c = busio.I2C(board.SCL, board.SDA) # Uses board.SCL and board.SDA
# Init Grove - Gas Sensor V2 (Multichannel)
sensor = MultichannelGasGMXXX(i2c)

def get_single_read():
  try:
    data = {
      "no2": sensor.measure_no2(),
      "c2h5oh": sensor.measure_c2h5oh(),
      "voc": sensor.measure_voc(),
      "co": sensor.measure_co(),
      "timestamp": int(time.time()),
      "success": True
    }
    return data
  except Exception as e:
    return {"success": False, "message": str(e)}


if __name__ == "__main__":
  print(json.dumps(get_single_read()))
