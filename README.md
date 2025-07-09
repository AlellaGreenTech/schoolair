# M5Stack CoreS3 Weather & Air Quality Station

This repository contains the firmware code for a localized weather and air quality monitoring station built using the M5Stack CoreS3. The station collects environmental data from various sensors and securely transmits it to a PostgreSQL database via HTTP POST request.

## Table of Contents

- [M5Stack CoreS3 Weather \& Air Quality Station](#m5stack-cores3-weather--air-quality-station)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [System Architecture](#system-architecture)
  - [Hardware Used](#hardware-used)
  - [Sensor Functioning](#sensor-functioning)
  - [Software Components](#software-components)
  - [Setup Guide](#setup-guide)
    - [1. M5Stack CoreS3 Setup](#1-m5stack-cores3-setup)
      - [Prerequisites](#prerequisites)
      - [Steps](#steps)
    - [2. PostgreSQL Database Setup](#2-postgresql-database-setup)
      - [Prerequisites](#prerequisites-1)
      - [Steps](#steps-1)
    - [3. Backend API Setup](#3-backend-api-setup)
      - [Prerequisites](#prerequisites-2)
      - [Steps](#steps-2)
  - [Usage](#usage)
  - [Future Improvements](#future-improvements)
  - [License](#license)

## Features

- **Real-time Data Collection:** Gathers environmental data including:
  - Temperature
  - Relative Humidity
  - PM2.5 (Fine Particulate Matter)
  - (Expandable for Pressure, Wind, Rain, other gases like CO/NO2 if sensors are added)
- **Secure Data Transmission:** Uses HTTP POST requests with an API Key to send data to a dedicated backend API.
- **Data Storage:** Stores all collected data in a PostgreSQL database for long-term analysis and historical tracking.
- **Modular Design:** Separates device logic from data storage for improved security, scalability, and maintainability.
- **Local UI (M5Stack Screen):** Provides immediate feedback on Wi-Fi status and data transmission success/failure.

## System Architecture

The system employs a client-server architecture to ensure reliable and secure data flow from the constrained M5Stack device to the PostgreSQL database.

**Why an Backend API?**

A direct connection from the M5Stack CoreS3 to a PostgreSQL database is **not feasible nor recommended** for several critical reasons:

- **Resource Constraints:** Microcontrollers like the ESP32-S3 lack the significant RAM, Flash memory, and processing power required to run complex PostgreSQL client drivers and handle the database protocol.
- **Protocol Complexity:** The PostgreSQL communication protocol is far more intricate than simple HTTP or MQTT, making direct implementation on an MCU highly impractical.
- **Severe Security Risks:** Embedding database credentials directly into the device's firmware would expose them to anyone with physical access or the ability to reverse-engineer the device, leading to full database compromise. A backend API acts as a secure gateway, protecting your database secrets.
- **Reliability & Networking:** Managing persistent database connections and robust error handling (e.g., network drops, database downtime) from a constrained device is extremely difficult. A backend server can buffer data, manage retries, and ensure data integrity more effectively.

Therefore, the backend API serves as a secure and reliable bridge, handling the heavy lifting of database interaction.

## Hardware Used

- **M5Stack CoreS3:** The central microcontroller unit, providing Wi-Fi connectivity, a display, and an easy-to-use development environment.
- **Sensor Modules:**
  - **Particulate Matter Sensor:** DFROBOT Gravity: PM2.5 Air Quality Sensor. This sensor uses laser scattering to count and size particles.
  - **Environmental Sensor:** ENV IV Unit (for Temperature, Humidity, Barometric Pressure). This combines multiple measurements into one compact module.

## Sensor Functioning

- **PM2.5 Sensor:** This sensor draws air through a chamber using a small fan. A laser shines through the air, and a detector measures the scattered light. The amount and pattern of scattered light allow the sensor to count and estimate the mass concentration of particles of different sizes, specifically PM1 (particles 1 micrometer or smaller), PM2.5 (particles 2.5 micrometers or smaller) and PM10 (particles 10 micrometers or smaller).
- **Temperature, Humidity & Pressure Sensor:**
  - **Temperature:** Uses a thermistor or a silicon-based temperature sensor to measure the ambient air temperature.
  - **Humidity:** Employs a capacitive sensor that measures the dielectric constant of the air, which changes with the amount of water vapor present.
  - **Barometric Pressure:** Uses a piezoresistive or capacitive pressure sensor to measure atmospheric pressure, which can also be used to infer altitude changes.

## Software Components

- **M5Stack CoreS3 Firmware:** Developed using UIFlow 2.0 (MicroPython) for ease of programming and M5Stack ecosystem integration.
- **Backend API:** Implemented using **Node-RED** for rapid development and easy integration with various services.
- **Database Connector:** Node-RED's PostgreSQL node for interacting with PostgreSQL.
- **Database:** PostgreSQL (can be self-hosted or a cloud service like AWS RDS, Azure Database for PostgreSQL, Google Cloud SQL for PostgreSQL, etc.).

## Setup Guide

Follow these steps to get your M5Stack Weather Station up and running.

### 1\. M5Stack CoreS3 Setup

#### Prerequisites

- An M5Stack CoreS3 device.
- Access to UIFlow 2.0 via `https://uiflow2.m5stack.com/`.
- Your Wi-Fi network SSID and password.
- The IP address/domain and port of your Backend API server.
- An API Key that matches what your backend expects.

#### Steps

1. **Connect to UIFlow:** Connect your M5Stack CoreS3 to UIFlow 2.0. Ensure it's in "Online Mode."
2. **Access Python Editor:** Switch to the Python editor within the UIFlow interface.
3. **Update Code:** Copy the MicroPython code from `main.py` file into the UIFlow editor.
4. **Configure Wi-Fi & API:**
      - Modify `SSID` and `PASSWORD` with your Wi-Fi credentials.
      - Update `API_URL` to point to your deployed Backend API (e.g., `'http://192.168.1.100:5000/sensordata'`).
      - Set `API_KEY` to the secret key you will use for authentication (e.g., `'YOUR_SECRET_API_KEY'`). **Ensure this matches the key configured in your backend.**
5. **Upload & Run:** Click the "Run" button in UIFlow to upload and execute the code on your M5Stack CoreS3.

### 2\. PostgreSQL Database Setup

#### Prerequisites

- A running PostgreSQL server (local or cloud-hosted).
- PostgreSQL superuser or equivalent permissions to create databases/users/tables.

#### Steps

1. **Create Database:** Create a new database for your sensor data (e.g., `weather_data`).

    ```sql
    CREATE DATABASE weather_data;
    ```

2. **Create User (Optional but Recommended):** Create a dedicated user with specific permissions for your application.

    ```sql
    CREATE USER your_db_user WITH PASSWORD 'your_db_password';
    GRANT ALL PRIVILEGES ON DATABASE weather_data TO your_db_user;
    ```

3. **Create Table:** Connect to your `weather_data` database and create a table to store sensor readings.

    ```sql
    \c weather_data; -- Connect to the newly created database

    CREATE TABLE aqs (
        id SERIAL PRIMARY KEY,
        inserted_at TIMESTAMPZ DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMPZ,
        dev_id VARCHAR(50) NOT NULL,
        temperature NUMERIC(5, 2),
        humidity NUMERIC(5, 2),
        pressure NUMERIC(7, 2),
        pm1 INTEGER,
        pm2_5 INTEGER,
        pm10 INTEGER
    );
    ```

### 3\. Backend API Setup

#### Prerequisites

- A running instance of Node-RED (locally or on a server).
- PostgreSQL node installed in Node-RED.

#### Steps

1. **Install Node-RED:**
   - Follow the [Node-RED installation guide](https://nodered.org/docs/getting-started/) for your platform.
   - Ensure you have the PostgreSQL node installed in Node-RED.

## Usage

Once both the M5Stack CoreS3 firmware and the Backend API are running, your weather station will begin collecting data and sending it to your PostgreSQL database at the configured interval (e.g., every 5 minutes).

You can then:

- Query your PostgreSQL database directly to view the raw data.
- Use a data visualization tool like **Grafana** (highly recommended) to connect to your PostgreSQL database and create interactive dashboards for human-readable insights.

## Future Improvements

- Add more sensor types (wind speed/direction, rain gauge, UV, CO, NO2, SO2, soil moisture).

## License

This project is licensed under the MIT License - see the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.