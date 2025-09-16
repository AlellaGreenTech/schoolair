class AirQualityMonitor {
    constructor() {
        this.classrooms = ['nursery', 'primary-a', 'primary-b', 'secondary-a', 'secondary-b'];
        this.gauges = {};
        this.currentData = {};
        this.historicalData = {};
        this.charts = {
            aqi: null,
            pollutants: null,
            environment: null
        };

        this.init();
        this.initModal();
        this.generateHistoricalData();
        this.startSimulation();
    }

    init() {
        this.classrooms.forEach(room => {
            this.initGauge(room);
            this.initClickListener(room);
        });
    }

    initClickListener(roomId) {
        const card = document.querySelector(`[data-room="${roomId}"]`);
        card.style.cursor = 'pointer';
        card.addEventListener('click', () => {
            this.showClassroomDetails(roomId);
        });
    }

    initGauge(roomId) {
        const canvas = document.getElementById(`gauge-${roomId}`);
        const ctx = canvas.getContext('2d');

        this.gauges[roomId] = {
            canvas,
            ctx,
            value: 0
        };

        this.drawGauge(roomId, 0);
    }

    drawGauge(roomId, value) {
        const { canvas, ctx } = this.gauges[roomId];
        const centerX = canvas.width / 2;
        const centerY = canvas.height / 2;
        const radius = 65;

        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // Background arc
        ctx.beginPath();
        ctx.arc(centerX, centerY, radius, 0.75 * Math.PI, 0.25 * Math.PI);
        ctx.strokeStyle = '#d0d7de';
        ctx.lineWidth = 10;
        ctx.stroke();

        // Value arc
        const startAngle = 0.75 * Math.PI;
        const endAngle = startAngle + (1.5 * Math.PI * value / 100);

        ctx.beginPath();
        ctx.arc(centerX, centerY, radius, startAngle, endAngle);

        // Color based on value
        if (value <= 30) {
            ctx.strokeStyle = '#4CAF50';
        } else if (value <= 60) {
            ctx.strokeStyle = '#FF9800';
        } else {
            ctx.strokeStyle = '#F44336';
        }

        ctx.lineWidth = 10;
        ctx.lineCap = 'round';
        ctx.stroke();

        // Center dot
        ctx.beginPath();
        ctx.arc(centerX, centerY, 4, 0, 2 * Math.PI);
        ctx.fillStyle = '#333';
        ctx.fill();

        // Update gauge value display
        document.getElementById(`value-${roomId}`).textContent = Math.round(value);
    }

    calculateSchoolAirQualityIndex(co2, pm25, temperature, humidity) {
        // Normalize each parameter to 0-100 scale
        const co2Score = this.normalizeCO2(co2);
        const pm25Score = this.normalizePM25(pm25);
        const temperatureScore = this.normalizeTemperature(temperature);
        const humidityScore = this.normalizeHumidity(humidity);

        // Apply weights: CO2×0.4 + PM2.5×0.3 + Temperature×0.15 + Humidity×0.15
        const index = (co2Score * 0.4) + (pm25Score * 0.3) + (temperatureScore * 0.15) + (humidityScore * 0.15);

        return Math.min(100, Math.max(0, index));
    }

    normalizeCO2(co2) {
        // CO2 scoring: <600 excellent, 600-800 good, 800-1000 moderate, >1000 poor
        if (co2 < 600) return 0;
        if (co2 < 800) return (co2 - 600) / 200 * 30; // 0-30
        if (co2 < 1000) return 30 + (co2 - 800) / 200 * 30; // 30-60
        return Math.min(100, 60 + (co2 - 1000) / 400 * 40); // 60-100
    }

    normalizePM25(pm25) {
        // PM2.5 scoring: <10 excellent, 10-20 good, 20-35 moderate, >35 poor
        if (pm25 < 10) return 0;
        if (pm25 < 20) return (pm25 - 10) / 10 * 30; // 0-30
        if (pm25 < 35) return 30 + (pm25 - 20) / 15 * 30; // 30-60
        return Math.min(100, 60 + (pm25 - 35) / 25 * 40); // 60-100
    }

    normalizeTemperature(temperature) {
        // Temperature scoring: 20-24°C optimal, penalize deviation
        const optimalTemperature = 22;
        const deviation = Math.abs(temperature - optimalTemperature);

        if (deviation <= 2) return 0; // 20-24°C excellent
        if (deviation <= 4) return (deviation - 2) / 2 * 30; // 0-30
        if (deviation <= 6) return 30 + (deviation - 4) / 2 * 30; // 30-60
        return Math.min(100, 60 + (deviation - 6) / 4 * 40); // 60-100
    }

    normalizeHumidity(humidity) {
        // Humidity scoring: 40-60% optimal, penalize deviation
        if (humidity >= 40 && humidity <= 60) return 0;

        let deviation;
        if (humidity < 40) {
            deviation = 40 - humidity;
        } else {
            deviation = humidity - 60;
        }

        if (deviation <= 10) return deviation / 10 * 30; // 0-30
        if (deviation <= 20) return 30 + (deviation - 10) / 10 * 30; // 30-60
        return Math.min(100, 60 + (deviation - 20) / 20 * 40); // 60-100
    }

    updateClassroom(roomId, data) {
        const { co2, pm25, temperature, humidity } = data;

        // Calculate air quality index
        const airQualityIndex = this.calculateSchoolAirQualityIndex(co2, pm25, temperature, humidity);

        // Update gauge
        this.drawGauge(roomId, airQualityIndex);

        // Update metrics display
        document.getElementById(`co2-${roomId}`).textContent = `${co2} ppm`;
        document.getElementById(`pm25-${roomId}`).textContent = `${pm25} μg/m³`;
        document.getElementById(`temp-${roomId}`).textContent = `${temperature} °C`;
        document.getElementById(`humidity-${roomId}`).textContent = `${humidity} %`;

        // Update status badge, fan, and alert message
        const statusBadge = document.getElementById(`status-${roomId}`);
        const fan = document.getElementById(`fan-${roomId}`);
        const alertMessage = document.getElementById(`alert-${roomId}`);

        if (airQualityIndex <= 30) {
            statusBadge.textContent = 'Good';
            statusBadge.className = 'status-badge good';
            fan.className = 'fan fan-slow';
            alertMessage.textContent = '';
            alertMessage.className = 'alert-message';
        } else if (airQualityIndex <= 60) {
            statusBadge.textContent = 'Moderate';
            statusBadge.className = 'status-badge moderate';
            fan.className = 'fan fan-medium';
            alertMessage.textContent = '🪟  Consider Ventilation';
            alertMessage.className = 'alert-message moderate';
        } else {
            statusBadge.textContent = 'Poor';
            statusBadge.className = 'status-badge poor';
            fan.className = 'fan fan-fast';
            alertMessage.textContent = '💨  Open Windows Now!';
            alertMessage.className = 'alert-message poor';
        }
    }

    generateRandomData() {
        return {
            co2: Math.round(400 + Math.random() * 800), // 400-1200 ppm
            pm25: Math.round(Math.random() * 50), // 0-50 μg/m³
            temperature: Math.round((18 + Math.random() * 8) * 10) / 10, // 18-26°C
            humidity: Math.round(30 + Math.random() * 40) // 30-70%
        };
    }

    startSimulation() {
        // Initial data load
        this.updateAllClassrooms();

        // Update every 5 seconds
        setInterval(() => {
            this.updateAllClassrooms();
        }, 5000);
    }

    updateAllClassrooms() {
        this.classrooms.forEach(classroomId => {
            const sensorData = this.generateRandomData();
            this.currentData[classroomId] = sensorData;
            this.updateClassroom(classroomId, sensorData);
        });
    }

    initModal() {
        const modal = document.getElementById('classroom-modal');
        const closeBtn = document.querySelector('.modal-close');

        closeBtn.addEventListener('click', () => {
            modal.style.display = 'none';
        });

        window.addEventListener('click', (event) => {
            if (event.target === modal) {
                modal.style.display = 'none';
            }
        });
    }

    generateHistoricalData() {
        this.classrooms.forEach(roomId => {
            this.historicalData[roomId] = this.generate24HourData();
        });
    }

    generate24HourData() {
        const data = [];
        const now = new Date();

        for (let i = 23; i >= 0; i--) {
            const time = new Date(now.getTime() - i * 60 * 60 * 1000);
            const hourData = {
                time: time.getHours() + ':00',
                co2: Math.round(400 + Math.random() * 800),
                pm25: Math.round(Math.random() * 50),
                temperature: Math.round((18 + Math.random() * 8) * 10) / 10,
                humidity: Math.round(30 + Math.random() * 40),
            };
            hourData.aqi = this.calculateSchoolAirQualityIndex(
                hourData.co2,
                hourData.pm25,
                hourData.temperature,
                hourData.humidity
            );
            data.push(hourData);
        }

        return data;
    }

    showClassroomDetails(roomId) {
        const modal = document.getElementById('classroom-modal');
        const title = document.getElementById('modal-title');

        // Set classroom name
        const classroomNames = {
            'nursery': '🧸 Nursery',
            'primary-a': '📚 Primary A',
            'primary-b': '✏️ Primary B',
            'secondary-a': '🧪 Secondary A',
            'secondary-b': '🎓 Secondary B'
        };

        title.textContent = classroomNames[roomId] + ' - 24h History';

        // Update current stats
        const current = this.currentData[roomId] || {};
        const aqi = this.calculateSchoolAirQualityIndex(
            current.co2 || 0,
            current.pm25 || 0,
            current.temperature || 20,
            current.humidity || 50
        );

        document.getElementById('modal-aqi').textContent = Math.round(aqi);
        document.getElementById('modal-co2').textContent = current.co2 + ' ppm';
        document.getElementById('modal-pm25').textContent = current.pm25 + ' μg/m³';
        document.getElementById('modal-temp').textContent = current.temperature + ' °C';
        document.getElementById('modal-humidity').textContent = current.humidity + ' %';

        const status = aqi <= 30 ? 'Good' : aqi <= 60 ? 'Moderate' : 'Poor';
        document.getElementById('modal-status').textContent = status;

        // Create chart
        this.createHistoryChart(roomId);

        // Show modal
        modal.style.display = 'block';
    }

    createHistoryChart(roomId) {
        // Destroy existing charts
        Object.values(this.charts).forEach(chart => {
            if (chart) chart.destroy();
        });

        const data = this.historicalData[roomId];
        const commonOptions = {
            responsive: true,
            maintainAspectRatio: false,
            interaction: {
                mode: 'index',
                intersect: false,
            },
            plugins: {
                legend: {
                    position: 'top',
                }
            },
            scales: {
                x: {
                    display: true,
                    title: {
                        display: true,
                        text: 'Time (24h)'
                    }
                }
            }
        };

        // AQI Chart (main)
        this.charts.aqi = new Chart(document.getElementById('aqi-chart'), {
            type: 'line',
            data: {
                labels: data.map(d => d.time),
                datasets: [{
                    label: 'Air Quality Index',
                    data: data.map(d => d.aqi),
                    borderColor: '#667eea',
                    backgroundColor: 'rgba(102, 126, 234, 0.2)',
                    borderWidth: 3,
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: {
                        display: true,
                        title: {
                            display: true,
                            text: 'AQI Level'
                        },
                        min: 0,
                        max: 100
                    }
                }
            }
        });

        // Pollutants Chart
        this.charts.pollutants = new Chart(document.getElementById('pollutants-chart'), {
            type: 'line',
            data: {
                labels: data.map(d => d.time),
                datasets: [
                    {
                        label: 'CO₂ (ppm)',
                        data: data.map(d => d.co2),
                        borderColor: '#4CAF50',
                        backgroundColor: 'rgba(76, 175, 80, 0.1)',
                        borderWidth: 2,
                        fill: false,
                        tension: 0.4,
                        yAxisID: 'y'
                    },
                    {
                        label: 'PM2.5 (μg/m³)',
                        data: data.map(d => d.pm25),
                        borderColor: '#FF9800',
                        backgroundColor: 'rgba(255, 152, 0, 0.1)',
                        borderWidth: 2,
                        fill: false,
                        tension: 0.4,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        title: {
                            display: true,
                            text: 'CO₂ (ppm)'
                        }
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        title: {
                            display: true,
                            text: 'PM2.5 (μg/m³)'
                        },
                        grid: {
                            drawOnChartArea: false,
                        },
                    }
                }
            }
        });

        // Environment Chart
        this.charts.environment = new Chart(document.getElementById('environment-chart'), {
            type: 'line',
            data: {
                labels: data.map(d => d.time),
                datasets: [
                    {
                        label: 'Temperature (°C)',
                        data: data.map(d => d.temperature),
                        borderColor: '#F44336',
                        backgroundColor: 'rgba(244, 67, 54, 0.1)',
                        borderWidth: 2,
                        fill: false,
                        tension: 0.4,
                        yAxisID: 'y'
                    },
                    {
                        label: 'Humidity (%)',
                        data: data.map(d => d.humidity),
                        borderColor: '#2196F3',
                        backgroundColor: 'rgba(33, 150, 243, 0.1)',
                        borderWidth: 2,
                        fill: false,
                        tension: 0.4,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        title: {
                            display: true,
                            text: 'Temperature (°C)'
                        },
                        min: 15,
                        max: 30
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        title: {
                            display: true,
                            text: 'Humidity (%)'
                        },
                        min: 20,
                        max: 80,
                        grid: {
                            drawOnChartArea: false,
                        },
                    }
                }
            }
        });
    }
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', () => {
    new AirQualityMonitor();
});