import board
import busio
from adafruit_bus_device.i2c_device import I2CDevice
import time

class MultichannelGasGMXXX:
    GM_102B = 0x01
    GM_302B = 0x03
    GM_502B = 0x05
    GM_702B = 0x07
    CHANGE_I2C_ADDR = 0x55
    WARMING_UP = 0xFE
    WARMING_DOWN = 0xFF

    def __init__(self, i2c_bus, address=0x08):
        self.i2c_device = I2CDevice(i2c_bus, address)
        self.address = address
        self.is_preheated = False
        self.preheated()

    def preheated(self):
        self._write_byte(self.WARMING_UP)
        self.is_preheated = True

    def un_preheated(self):
        self._write_byte(self.WARMING_DOWN)
        self.is_preheated = False

    def set_address(self, address):
        self.address = address
        self.preheated()

    def change_address(self, address):
        if address == 0 or address > 127:
            address = 0x08
        self._write_byte(self.CHANGE_I2C_ADDR, address)
        self.address = address

    def _write_byte(self, cmd, value=None):
        with self.i2c_device as i2c:
            if value is None:
                i2c.write(bytes([cmd]))
            else:
                i2c.write(bytes([cmd, value]))
        time.sleep(0.001)

    def _read_bytes(self, num_bytes):
        with self.i2c_device as i2c:
            result = bytearray(num_bytes)
            i2c.readinto(result)
        return result

    def _read_32bit(self):
        result = self._read_bytes(4)
        return int.from_bytes(result, 'little')

    def get_gm102b(self):
        if not self.is_preheated:
            self.preheated()
        self._write_byte(self.GM_102B)
        return self._read_32bit()

    def get_gm302b(self):
        if not self.is_preheated:
            self.preheated()
        self._write_byte(self.GM_302B)
        return self._read_32bit()

    def get_gm502b(self):
        if not self.is_preheated:
            self.preheated()
        self._write_byte(self.GM_502B)
        return self._read_32bit()

    def get_gm702b(self):
        if not self.is_preheated:
            self.preheated()
        self._write_byte(self.GM_702B)
        return self._read_32bit()

    def calc_vol(self, adc, verf=3.3, resolution=1023):
        return (adc * verf) / (resolution * 1.0)

    def measure_no2(self):
        return self.get_gm102b()

    def measure_c2h5oh(self):
        return self.get_gm302b()

    def measure_voc(self):
        return self.get_gm502b()

    def measure_co(self):
        return self.get_gm702b()

