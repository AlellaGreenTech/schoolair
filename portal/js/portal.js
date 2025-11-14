/**
 * School Portal Main JavaScript
 * Handles portal initialization, data loading, and user interactions
 */

let portal;
let currentSchool;

// Initialize portal on page load
document.addEventListener('DOMContentLoaded', async () => {
    portal = new SchoolPortal();
    await initializePortal();
});

async function initializePortal() {
    // Show loading screen
    const loading = document.getElementById('loading');

    try {
        // Load school configuration
        currentSchool = await portal.loadSchoolConfig();

        if (!currentSchool && portal.schoolSlug) {
            // School not found
            alert('School not found. Redirecting to main site.');
            window.location.href = 'https://schoolair.org';
            return;
        }

        if (!currentSchool) {
            // No subdomain - for testing, use BFIS
            portal.schoolSlug = 'bfis';
            currentSchool = await portal.loadSchoolConfig();
        }

        // Update page with school info
        updateSchoolInfo();

        // Load all portal sections
        loadUsers();
        loadAPIKeys();
        loadThresholds();
        loadCharts();

        // Hide loading screen
        loading.classList.add('hidden');

    } catch (error) {
        console.error('Error initializing portal:', error);
        alert('Error loading portal. Please try again.');
    }
}

function updateSchoolInfo() {
    // Update navigation
    document.getElementById('schoolName').textContent = currentSchool.name;
    document.title = `${currentSchool.name} Portal - SchoolAIR`;

    // Update cover section
    const coverHero = document.getElementById('coverHero');
    if (currentSchool.coverImage) {
        coverHero.style.backgroundImage = `url('${currentSchool.coverImage}')`;
    }

    document.getElementById('coverSchoolName').textContent = currentSchool.name;
    document.getElementById('coverLocation').textContent = currentSchool.location;

    // Update stats
    document.getElementById('statSensors').textContent = currentSchool.stats.sensors;
    document.getElementById('statStudents').textContent = currentSchool.stats.students;
    document.getElementById('statData').textContent = formatNumber(currentSchool.stats.dataPoints);
    document.getElementById('statAlerts').textContent = currentSchool.stats.alerts;
}

function formatNumber(num) {
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(0) + 'K';
    return num.toString();
}

// ============================================
// USERS SECTION
// ============================================

function loadUsers() {
    const users = MockData.users.filter(u => u.school === portal.schoolSlug);
    renderUsersTable(users);

    // Add role filter functionality
    document.querySelectorAll('.role-tab').forEach(tab => {
        tab.addEventListener('click', (e) => {
            // Update active tab
            document.querySelectorAll('.role-tab').forEach(t => t.classList.remove('active'));
            e.target.classList.add('active');

            // Filter users
            const role = e.target.dataset.role;
            const filtered = role === 'all'
                ? users
                : users.filter(u => u.role === role);

            renderUsersTable(filtered);
        });
    });
}

function renderUsersTable(users) {
    const tbody = document.getElementById('usersTableBody');
    tbody.innerHTML = users.map(user => `
        <tr>
            <td><strong>${user.name}</strong></td>
            <td>${user.email}</td>
            <td><span class="role-badge role-${user.role}">${user.role}</span></td>
            <td>${formatDate(user.joinedDate)}</td>
            <td>${formatDate(user.lastActive)}</td>
            <td>${user.apiKeysCount}</td>
            <td>
                <div class="action-buttons">
                    <button class="btn-icon" onclick="editUser(${user.id})" title="Edit">
                        <i class="fas fa-edit"></i>
                    </button>
                    <button class="btn-icon" onclick="viewUserKeys(${user.id})" title="API Keys">
                        <i class="fas fa-key"></i>
                    </button>
                    <button class="btn-icon danger" onclick="deleteUser(${user.id})" title="Delete">
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            </td>
        </tr>
    `).join('');
}

function formatDate(dateString) {
    const date = new Date(dateString);
    const now = new Date();
    const diffDays = Math.floor((now - date) / (1000 * 60 * 60 * 24));

    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Yesterday';
    if (diffDays < 7) return `${diffDays} days ago`;

    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

// ============================================
// API KEYS SECTION
// ============================================

function loadAPIKeys() {
    const keys = MockData.apiKeys;
    const grid = document.getElementById('apiKeysGrid');

    grid.innerHTML = keys.map(key => `
        <div class="api-key-card">
            <div class="key-header">
                <div>
                    <div class="key-name">${key.name}</div>
                    <span class="role-badge role-${key.role}">${key.role}</span>
                </div>
                <span class="key-status ${key.status}">${key.status}</span>
            </div>
            <div class="key-value">${key.key}</div>
            <div class="key-meta">
                <div>
                    <span>Created by:</span>
                    <strong>${key.createdBy}</strong>
                </div>
                <div>
                    <span>Created:</span>
                    <strong>${formatDate(key.createdDate)}</strong>
                </div>
                <div>
                    <span>Last used:</span>
                    <strong>${key.lastUsed ? formatDate(key.lastUsed) : 'Never'}</strong>
                </div>
                <div>
                    <span>API calls:</span>
                    <strong>${key.usageCount.toLocaleString()}</strong>
                </div>
                <div style="margin-top: 0.5rem;">
                    <span>Permissions:</span>
                </div>
                <div style="flex-wrap: wrap; gap: 0.25rem; display: flex;">
                    ${key.permissions.map(p => `
                        <span style="background: #e0f2f1; color: #00796b; padding: 0.15rem 0.5rem; border-radius: 4px; font-size: 0.75rem;">${p}</span>
                    `).join('')}
                </div>
            </div>
            <div class="action-buttons" style="margin-top: 1rem; justify-content: flex-end;">
                <button class="btn-icon" onclick="copyAPIKey('${key.key}')" title="Copy">
                    <i class="fas fa-copy"></i>
                </button>
                <button class="btn-icon" onclick="regenerateKey(${key.id})" title="Regenerate">
                    <i class="fas fa-sync"></i>
                </button>
                <button class="btn-icon danger" onclick="revokeKey(${key.id})" title="Revoke">
                    <i class="fas fa-ban"></i>
                </button>
            </div>
        </div>
    `).join('');
}

function copyAPIKey(key) {
    navigator.clipboard.writeText(key);
    alert('API key copied to clipboard!');
}

// ============================================
// THRESHOLDS SECTION
// ============================================

function loadThresholds() {
    const thresholds = MockData.thresholds;
    const tbody = document.getElementById('thresholdsTableBody');

    tbody.innerHTML = thresholds.map(threshold => `
        <tr>
            <td><strong>${threshold.parameter.toUpperCase()}</strong></td>
            <td>${threshold.value} ${threshold.unit}</td>
            <td>${threshold.condition}</td>
            <td>
                <div style="max-width: 300px;">
                    <div style="font-weight: 600; margin-bottom: 0.25rem;">${threshold.action}</div>
                    <div style="font-size: 0.85rem; color: #64748b;">${threshold.actionDetails}</div>
                </div>
            </td>
            <td><span class="severity-badge severity-${threshold.severity}">${threshold.severity}</span></td>
            <td>
                <label class="toggle-switch">
                    <input type="checkbox" ${threshold.enabled ? 'checked' : ''} onchange="toggleThreshold(${threshold.id})">
                    <span class="toggle-slider"></span>
                </label>
            </td>
            <td>
                <div class="action-buttons">
                    <button class="btn-icon" onclick="editThreshold(${threshold.id})" title="Edit">
                        <i class="fas fa-edit"></i>
                    </button>
                    <button class="btn-icon danger" onclick="deleteThreshold(${threshold.id})" title="Delete">
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            </td>
        </tr>
    `).join('');
}

function toggleThreshold(id) {
    console.log('Toggle threshold:', id);
    // In production, this would update Supabase
    alert(`Threshold ${id} toggled!`);
}

// ============================================
// CHARTS SECTION
// ============================================

function loadCharts() {
    // CO2 Chart
    createLineChart('co2Chart', MockData.sensorData.co2, 'CO₂ (ppm)', '#dc2626');

    // Temperature Chart
    createLineChart('tempChart', MockData.sensorData.temperature, 'Temperature (°C)', '#2563eb');

    // Humidity Chart
    createLineChart('humidityChart', MockData.sensorData.humidity, 'Humidity (%)', '#16a34a');
}

function createLineChart(canvasId, data, label, color) {
    const ctx = document.getElementById(canvasId).getContext('2d');

    new Chart(ctx, {
        type: 'line',
        data: {
            labels: data.map(d => new Date(d.timestamp).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })),
            datasets: [{
                label: label,
                data: data.map(d => d.value.toFixed(1)),
                borderColor: color,
                backgroundColor: color + '20',
                borderWidth: 2,
                tension: 0.4,
                fill: true,
                pointRadius: 0,
                pointHoverRadius: 5
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                }
            },
            scales: {
                y: {
                    beginAtZero: false,
                    grid: {
                        color: '#f1f5f9'
                    }
                },
                x: {
                    grid: {
                        display: false
                    },
                    ticks: {
                        maxTicksLimit: 12
                    }
                }
            }
        }
    });
}

// ============================================
// UTILITY FUNCTIONS
// ============================================

function scrollToSection(sectionId) {
    document.getElementById(sectionId).scrollIntoView({ behavior: 'smooth' });
}

function showAddUserModal() {
    alert('Add User modal would open here.\nIn production, this would show a form to create a new user with role selection.');
}

function editUser(id) {
    alert(`Edit user ${id}\nIn production, this would open an edit form.`);
}

function viewUserKeys(id) {
    alert(`View API keys for user ${id}\nIn production, this would show all keys for this user.`);
}

function deleteUser(id) {
    if (confirm('Are you sure you want to delete this user?')) {
        alert(`User ${id} deleted!`);
    }
}

function showCreateKeyModal() {
    alert('Create API Key modal would open here.\nYou would select:\n- Key name\n- Role\n- Specific permissions\n- Expiration date (optional)');
}

function regenerateKey(id) {
    if (confirm('Regenerate this API key? The old key will be immediately revoked.')) {
        alert(`Key ${id} regenerated!`);
    }
}

function revokeKey(id) {
    if (confirm('Are you sure you want to revoke this API key? This action cannot be undone.')) {
        alert(`Key ${id} revoked!`);
    }
}

function showAddThresholdModal() {
    alert('Add Threshold modal would open here.\nYou would configure:\n- Parameter (CO2, temp, humidity, etc.)\n- Threshold value\n- Condition (above/below)\n- Action to take\n- Severity level');
}

function editThreshold(id) {
    alert(`Edit threshold ${id}\nIn production, this would open an edit form.`);
}

function deleteThreshold(id) {
    if (confirm('Are you sure you want to delete this threshold?')) {
        alert(`Threshold ${id} deleted!`);
    }
}

function exportData() {
    alert('Export Data\n\nIn production, this would:\n- Generate CSV/Excel file with selected date range\n- Include all sensor readings\n- Provide download link');
}
