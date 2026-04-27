#!/usr/bin/env python3
import sys
import subprocess
import json
import os
import datetime


VERSION = "1.0.4"
BINARY_PATH = "/home/admin/i2c/sen6x/sen6x_d"


def get_last_modified():
    # os.path.realpath(__file__) gets the full path to THIS script
    path = os.path.realpath(__file__)
    timestamp = os.path.getmtime(path)
    
    # Convert the timestamp to a readable format
    dt_object = datetime.datetime.fromtimestamp(timestamp)
    return dt_object.strftime("%Y-%m-%d %H:%M:%S")

def run_cli():
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        
        # Handle -v by passing it to the C binary
        if arg == "-v":
            print(f"SchoolAir v{VERSION}")
            print(f"Build Date (Last Edited): {get_last_modified()}")
            subprocess.run([BINARY_PATH, "-v"])
            return

        # Handle --status by reading the JSON file your C code generates
        if arg == "--status":
            try:
                with open("/home/admin/i2c/sen6x/sen6x.json", "r") as f:
                    data = json.load(f)
                    print(f"Latest Reading ({data['timestamp']}):")
                    print(f"Temp: {data['temp']}°C | Humidity: {data['humidity']}%")
            except FileNotFoundError:
                print("No active readings found. Is the sensor service running?")
            return

    print("Usage: schoolair [-v | --status]")

if __name__ == "__main__":
    run_cli()
