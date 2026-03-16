#include "sen63c_i2c.h"
#include "sensirion_common.h"
#include "sensirion_i2c_hal.h"
#include <inttypes.h>  // PRIx64
#include <stdio.h>     // printf
#include <time.h>

#define sensirion_hal_sleep_us sensirion_i2c_hal_sleep_usec

int main(void) {
    int16_t error = NO_ERROR;
    sensirion_i2c_hal_init();
    sen63c_init(SEN63C_I2C_ADDR_6B);

    error = sen63c_device_reset();
    if (error != NO_ERROR) {
        printf("error executing device_reset(): %i\n", error);
        return error;
    }
    sensirion_hal_sleep_us(1200000);
    int8_t serial_number[32] = {0};
    error = sen63c_get_serial_number(serial_number, 32);
    if (error != NO_ERROR) {
        printf("error executing get_serial_number(): %i\n", error);
        return error;
    }
    printf("serial_number: %s\n", serial_number);
    error = sen63c_start_continuous_measurement();
    if (error != NO_ERROR) {
        printf("error executing start_continuous_measurement(): %i\n", error);
        return error;
    }
    float mass_concentration_pm1p0 = 0.0;
    float mass_concentration_pm2p5 = 0.0;
    float mass_concentration_pm4p0 = 0.0;
    float mass_concentration_pm10p0 = 0.0;
    float humidity = 0.0;
    float temperature = 0.0;
    uint16_t co2 = 0;
    while (1) {
        error = sen63c_read_measured_values(
            &mass_concentration_pm1p0, &mass_concentration_pm2p5,
            &mass_concentration_pm4p0, &mass_concentration_pm10p0, &humidity,
            &temperature, &co2);
        if (co2 != 32767) break;
        sensirion_i2c_hal_sleep_usec(2000000);
    }

    uint8_t sleeptime = 60; // 1 minute between samples
    while (1) {
        // First, check if the PREVIOUS read was successful
        if (error == NO_ERROR) {
            FILE *f = fopen("/tmp/sen6x.json.tmp", "w");
            if (f) {
                char timestr[20];
                time_t now = time(NULL);
                strftime(timestr, sizeof(timestr), "%Y-%m-%d %H:%M:%S", localtime(&now));
                // Meticulous mapping of all SEN63C parameters
                fprintf(f, "{"
                           "\"timestamp\": \"%s\", "
                           "\"temp\": %0.2f, "
                           "\"humidity\": %0.2f, "
                           "\"co2\": %u, "
                           "\"pm10\": %0.1f, "
                           "\"pm25\": %0.1f, "
                           "\"pm40\": %0.1f, "
                           "\"pm100\": %0.1f"
                           "}\n",
                        timestr,
                        temperature,
                        humidity,
                        co2,
                        mass_concentration_pm1p0,
                        mass_concentration_pm2p5,
                        mass_concentration_pm4p0,
                        mass_concentration_pm10p0);
                fclose(f);
                rename("/tmp/sen6x.json.tmp", "/tmp/sen6x.json");
            }
        } else {
            // Real errors are logged to systemd journal
            fprintf(stderr, "[%lld] Sensor Read Error: %d\n", (long long)time(NULL), error);
        }

        // Wait for the next interval
        sensirion_hal_sleep_us(sleeptime * 1000000);

        // Perform the next read
        error = sen63c_read_measured_values(
            &mass_concentration_pm1p0, &mass_concentration_pm2p5,
            &mass_concentration_pm4p0, &mass_concentration_pm10p0,
            &humidity, &temperature, &co2);
    }
    return 0;
}
