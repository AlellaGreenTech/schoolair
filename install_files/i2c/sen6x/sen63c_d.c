#include "sen63c_i2c.h"
#include "sen65_i2c.h"
#include "sensirion_common.h"
#include "sensirion_i2c_hal.h"
#include <inttypes.h>  // PRIx64
#include <stdio.h>     // printf
#include <time.h>
#include <string.h>

#define sensirion_hal_sleep_us sensirion_i2c_hal_sleep_usec
#define sen6x_init sen63c_init
#define sen6x_device_reset sen63c_device_reset
#define sen6x_get_serial sen63c_get_serial_number
#define sen6x_get_product_name sen63c_get_product_name
#define sen6x_start_continuous_measurement sen63c_start_continuous_measurement

// Define sensor types
typedef enum {
    SEN63C,
    SEN65,
    SENSOR_UNKNOWN
} sensor_type_t;

typedef struct {
    float pm10;
    float pm25;
    float pm40;
    float pm100;
    float temperature;
    float humidity;
    union {
        struct {
            uint16_t co2;
        } sen63c_data;
        struct {
            float voc;
            float nox;
        } sen65_data;
    } sensor_specific;
} sensor_reading_t;

int sen6x_read_measured_values(sensor_reading_t* r, sensor_type_t type){
    if (type == SEN63C)
        return sen63c_read_measured_values(&(r->pm10), &(r->pm25), &(r->pm40), &(r->pm100),
            &(r->humidity), &(r->temperature), &(r->sensor_specific.sen63c_data.co2));
    else if (type == SEN65)
        return sen65_read_measured_values(&(r->pm10), &(r->pm25), &(r->pm40), &(r->pm100),
            &(r->humidity), &(r->temperature),
            &(r->sensor_specific.sen65_data.voc), &(r->sensor_specific.sen65_data.nox));
    return -1;
}

// Detection function
sensor_type_t detect_sensor_type(void) {
    int8_t product_name[32] = {0};
    int16_t error;

    error = sen6x_get_product_name(product_name, 32);

    if (error != NO_ERROR) {
        printf("I2C Communication Error during detection: %i\n", error);
        return SENSOR_UNKNOWN;
    }
    // Convert to standard char pointer for string operations
    char* name_ptr = (char*)product_name;

    printf("Hardware identified as: %s\n", name_ptr);

    if (strstr(name_ptr, "SEN63") != NULL) {
        return SEN63C;
    }

    if (strstr(name_ptr, "SEN65") != NULL) {
        return SEN65;
    }

    return SENSOR_UNKNOWN;
}

void write_json_output(sensor_reading_t* r, sensor_type_t type) {
    FILE *f = fopen("/home/admin/i2c/sen6x/.sen6x.json.tmp", "w");
    if (!f) return;

    char timestr[20];
    time_t now = time(NULL);
    strftime(timestr, sizeof(timestr), "%Y-%m-%d %H:%M:%S", localtime(&now));

    fprintf(f, "{\"timestamp\": \"%s\", \"temp\": %0.2f, \"humidity\": %0.2f, ",
            timestr, r->temperature, r->humidity);

    if (type == SEN63C) {
        fprintf(f, "\"co2\": %u, ", r->sensor_specific.sen63c_data.co2);
    } else {
        fprintf(f, "\"voc\": %0.1f, \"nox\": %0.1f, ",
                r->sensor_specific.sen65_data.voc,
                r->sensor_specific.sen65_data.nox);
    }

    fprintf(f, "\"pm10\": %0.1f, \"pm25\": %0.1f, \"pm40\": %0.1f, \"pm100\": %0.1f}\n",
            r->pm10, r->pm25, r->pm40, r->pm100);

    fclose(f);
    rename("/home/admin/i2c/sen6x/.sen6x.json.tmp", "/home/admin/i2c/sen6x/sen6x.json");
}


int main(int argc, char *argv[]) {
    int16_t error = NO_ERROR;
    sensirion_i2c_hal_init();

    sen6x_init(0x6b);

    sensor_type_t sensor_type = detect_sensor_type();
    if (argc > 1 && strcmp(argv[1], "-v") == 0) {
        if (sensor_type == SEN63C) printf("Main Sensor: SEN63C\n");
        else if (sensor_type == SEN65) printf("Main Sensor: SEN65\n");
        else printf("Main Sensor: Unknown\n");
        return 0; // Exit early
    }
    if (sensor_type == SENSOR_UNKNOWN) {
        printf("Error: Unable to detect sensor type\n");
        return -1;
    }

    if (sensor_type == SEN65)
        sen65_init(0x6b);

    error = sen6x_device_reset();
    if (error != NO_ERROR) {
        printf("error executing device_reset(): %i\n", error);
        return error;
    }
    sensirion_hal_sleep_us(1200000);

    int8_t serial_number[32] = {0};
    error = sen6x_get_serial(serial_number, 32);
    if (error != NO_ERROR) {
        printf("error executing get_serial_number(): %i\n", error);
        return error;
    }
    printf("serial_number: %s\n", serial_number);

    error = sen6x_start_continuous_measurement();
    if (error != NO_ERROR) {
        printf("error executing start_continuous_measurement(): %i\n", error);
        return error;
    }

    sensor_reading_t reading;
    for (uint8_t retry_count = 0 ; retry_count < 10 ; ++retry_count) {
        error = sen6x_read_measured_values(&reading, sensor_type);
        if (sensor_type == SEN63C && reading.sensor_specific.sen63c_data.co2 != 32767) break;
        sensirion_i2c_hal_sleep_usec(2000000);
    }

    uint8_t sleeptime = 60; // 1 minute between samples
    while (1) {
        // First, check if the PREVIOUS read was successful
        if (error == NO_ERROR) {
            write_json_output(&reading, sensor_type);
        } else {
            // Real errors are logged to systemd journal
            fprintf(stderr, "[%lld] Sensor Read Error: %d\n", (long long)time(NULL), error);
        }

        // Wait for the next interval
        sensirion_hal_sleep_us(sleeptime * 1000000);

        // Perform the next read
        error = sen6x_read_measured_values(&reading, sensor_type);
    }
    return 0;
}
