#!/usr/bin/python3
import sys
import time
import json
from DFRobot_Ozone import *

COLLECT_NUMBER   = 20              # collect number, the collection range is 1-100
IIC_MODE         = 0x01            # default use IIC1

'''
   The first  parameter is to select i2c0 or i2c1
   The second parameter is the i2c device address
   The default address for i2c is OZONE_ADDRESS_3
      OZONE_ADDRESS_0        0x70
      OZONE_ADDRESS_1        0x71
      OZONE_ADDRESS_2        0x72
      OZONE_ADDRESS_3        0x73
'''
ozone = DFRobot_Ozone_IIC(IIC_MODE ,OZONE_ADDRESS_3)
'''
  The module is configured in automatic mode or passive
    MEASURE_MODE_AUTOMATIC  active  mode
    MEASURE_MODE_PASSIVE    passive mode
''' 
ozone.set_mode(MEASURE_MODE_AUTOMATIC)

''' Smooth data collection the collection range is 1-100 '''
def get_single_read():
  try:
    data = {
      "ozone": ozone.get_ozone_data(COLLECT_NUMBER),
      "timestamp": int(time.time()),
      "success": True
    }
    return data
  except Exception as e:
    return {"success": False, "message": str(e)}


if __name__ == "__main__":
  print(json.dumps(get_single_read()))
