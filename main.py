from machine import I2C, Pin
import time
import M5
import m5ui
import requests2
import time
import ntptime


page0 = None
http_req = None
i2c0 = None
timezone_offset = None


# I2C address of the sensors
ENV_ADDR_PM25 = 0x19
ENV_ADDR_SHT40 = 0x44
ENV_ADDR_BMP280 = 0x76


bmp_calib = {}
t_fine = 0


# Measurement registers
PM1_0_STANDARD = 0x05
PM2_5_STANDARD = 0x07
PM10_STANDARD = 0x09


def bmp_read_calibration():
    """Read and store BMP280 calibration registers."""
    # Read calibration block (0x88..0xA1)
    calib = i2c0.readfrom_mem(ENV_ADDR_BMP280, 0x88, 24)
    # Unpack little-endian unsigned and signed values
    bmp_calib["dig_T1"] = calib[0] | (calib[1] << 8)
    bmp_calib["dig_T2"] = (
        calib[2] | (calib[3] << 8)
        if calib[3] < 128
        else calib[2] | (calib[3] << 8) - (1 << 16)
    )
    bmp_calib["dig_T3"] = (
        calib[4] | (calib[5] << 8)
        if calib[5] < 128
        else calib[4] | (calib[5] << 8) - (1 << 16)
    )
    bmp_calib["dig_P1"] = calib[6] | (calib[7] << 8)
    bmp_calib["dig_P2"] = (
        calib[8] | (calib[9] << 8)
        if calib[9] < 128
        else calib[8] | (calib[9] << 8) - (1 << 16)
    )
    bmp_calib["dig_P3"] = (
        calib[10] | (calib[11] << 8)
        if calib[11] < 128
        else calib[10] | (calib[11] << 8) - (1 << 16)
    )
    bmp_calib["dig_P4"] = (
        calib[12] | (calib[13] << 8)
        if calib[13] < 128
        else calib[12] | (calib[13] << 8) - (1 << 16)
    )
    bmp_calib["dig_P5"] = (
        calib[14] | (calib[15] << 8)
        if calib[15] < 128
        else calib[14] | (calib[15] << 8) - (1 << 16)
    )
    bmp_calib["dig_P6"] = (
        calib[16] | (calib[17] << 8)
        if calib[17] < 128
        else calib[16] | (calib[17] << 8) - (1 << 16)
    )
    bmp_calib["dig_P7"] = (
        calib[18] | (calib[19] << 8)
        if calib[19] < 128
        else calib[18] | (calib[19] << 8) - (1 << 16)
    )
    bmp_calib["dig_P8"] = (
        calib[20] | (calib[21] << 8)
        if calib[21] < 128
        else calib[20] | (calib[21] << 8) - (1 << 16)
    )
    bmp_calib["dig_P9"] = (
        calib[22] | (calib[23] << 8)
        if calib[23] < 128
        else calib[22] | (calib[23] << 8) - (1 << 16)
    )


def compensate_temperature(raw_temp):
    """Returns tuple (temp_C, t_fine)"""
    global t_fine
    var1 = ((raw_temp / 16384.0) - (bmp_calib["dig_T1"] / 1024.0)) * bmp_calib["dig_T2"]
    var2 = (((raw_temp / 131072.0) - (bmp_calib["dig_T1"] / 8192.0)) ** 2) * bmp_calib[
        "dig_T3"
    ]
    t_fine = int(var1 + var2)
    temp = (var1 + var2) / 5120.0
    return temp


def compensate_pressure(raw_press):
    """Returns pressure in Pa"""
    global t_fine
    var1 = t_fine / 2.0 - 64000.0
    var2 = var1 * var1 * bmp_calib["dig_P6"] / 32768.0
    var2 = var2 + var1 * bmp_calib["dig_P5"] * 2.0
    var2 = var2 / 4.0 + bmp_calib["dig_P4"] * 65536.0
    var1 = (
        bmp_calib["dig_P3"] * var1 * var1 / 524288.0 + bmp_calib["dig_P2"] * var1
    ) / 524288.0
    var1 = (1.0 + var1 / 32768.0) * bmp_calib["dig_P1"]
    if var1 == 0:
        return 0  # avoid division by zero
    press = 1048576.0 - raw_press
    press = ((press - var2 / 4096.0) * 6250.0) / var1
    var1 = bmp_calib["dig_P9"] * press * press / 2147483648.0
    var2 = press * bmp_calib["dig_P8"] / 32768.0
    press = press + (var1 + var2 + bmp_calib["dig_P7"]) / 16.0
    return press  # already in Pa


def read_pm(reg):
    """Reads 2 bytes from the given register and returns the value as an integer"""
    try:
        i2c0.writeto(ENV_ADDR_PM25, bytes([reg]))
        time.sleep_ms(50)  # Small delay to ensure response
        data = i2c0.readfrom(ENV_ADDR_PM25, 2)
        return (data[0] << 8) | data[1]
    except Exception as e:
        print(f"Error reading {hex(reg)}:", e)
        return -1


def read_env_sht40():
    try:
        # Send SHT40 measurement command: High repeatability, clock stretching disabled
        i2c0.writeto(ENV_ADDR_SHT40, b"\xfd")
        time.sleep_ms(20)
        data = i2c0.readfrom(ENV_ADDR_SHT40, 6)

        raw_temp = (data[0] << 8) | data[1]
        raw_hum = (data[3] << 8) | data[4]

        # Convert raw values to temperature (°C) and humidity (%)
        temp = -45 + 175 * (raw_temp / 65535.0)
        hum = 100 * (raw_hum / 65535.0)

        return round(temp, 2), round(hum, 2)
    except Exception as e:
        print("SHT40 read error:", e)
        return None, None


def read_bmp280_pressure():
    # Read raw pressure & temp (6 bytes)
    data = i2c0.readfrom_mem(ENV_ADDR_BMP280, 0xF7, 6)
    raw_press = (data[0] << 12) | (data[1] << 4) | (data[2] >> 4)
    raw_temp = (data[3] << 12) | (data[4] << 4) | (data[5] >> 4)
    # compute actual values
    compensate_temperature(raw_temp)
    press_pa = compensate_pressure(raw_press)
    return round(press_pa, 2)


def setup():
    global page0, i2c0, timezone_offset
    M5.begin()
    m5ui.init()
    page0 = m5ui.M5Page(bg_c=0xFFFFFF)
    page0.screen_load()
    i2c0 = I2C(0, scl=Pin(1), sda=Pin(2), freq=100000)
    print("Sensor ready at address", hex(ENV_ADDR_PM25))
    # configure BMP280: normal mode, temp+press oversampling x1, standby 250ms
    i2c0.writeto_mem(ENV_ADDR_BMP280, 0xF4, b"\x27")
    i2c0.writeto_mem(ENV_ADDR_BMP280, 0xF5, b"\xa0")
    # read calibration data once
    bmp_read_calibration()
    print("BMP280 calibration loaded.")
    ntptime.host = "time.google.com"  # ou 'pool.ntp.org'
    try:
        print("Syncing time with NTP...")
        ntptime.settime()
        print("Time synchronized successfully.")
    except Exception as e:
        print("Error during NTP synchronization:", e)

    timezone_offset = 2 * 3600


def loop():
    global http_req
    pm1 = read_pm(PM1_0_STANDARD)
    pm2_5 = read_pm(PM2_5_STANDARD)
    pm10 = read_pm(PM10_STANDARD)

    current_time = time.localtime(time.time() + timezone_offset)
    temp, hum = read_env_sht40()
    pressure = read_bmp280_pressure()

    print(f"Temperature: {temp} °C")
    print(f"Humidity: {hum} %")
    print(f"Pressure: {pressure} Pa")

    print(f"PM1.0: {pm1} µg/m³")
    print(f"PM2.5: {pm2_5} µg/m³")
    print(f"PM10 : {pm10} µg/m³")
    print("-" * 30)
    http_req = requests2.post(
        "https://cp.iotvision.co/aqc/apiv0",
        json={
            "device_id": "agt_aqs_1",
            "timestamp": current_time,
            "temperature": temp,
            "humidity": hum,
            "pressure": pressure,
            "pm1": pm1,
            "pm2_5": pm2_5,
            "pm10": pm10,
        },
        headers={
            "Content-Type": "application/json",
            "Authorization": "Basic Y2FucGljYXJkOkNhbWlCYWl4RGVUaWFuYTE4MTg=",
        },
    )

    time.sleep(2)


if __name__ == "__main__":
    try:
        setup()
        while True:
            loop()
    except (Exception, KeyboardInterrupt) as e:
        try:
            m5ui.deinit()
            from utility import print_error_msg

            print_error_msg(e)
        except ImportError:
            print("Please update to the latest firmware")
