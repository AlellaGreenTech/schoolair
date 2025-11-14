/**
 * Mock Data for School Portal
 * This will be replaced with Supabase queries in production
 */

const MockData = {
    // Users and their roles
    users: [
        {
            id: 1,
            name: 'Maria Garcia',
            email: 'mgarcia@bfis.edu',
            role: 'admin',
            school: 'bfis',
            joinedDate: '2024-06-15',
            lastActive: '2024-11-15',
            apiKeysCount: 2
        },
        {
            id: 2,
            name: 'John Smith',
            email: 'jsmith@bfis.edu',
            role: 'teacher',
            school: 'bfis',
            joinedDate: '2024-07-01',
            lastActive: '2024-11-14',
            apiKeysCount: 1
        },
        {
            id: 3,
            name: 'Emma Chen',
            email: 'echen@bfis.edu',
            role: 'student',
            school: 'bfis',
            joinedDate: '2024-09-01',
            lastActive: '2024-11-15',
            apiKeysCount: 0
        },
        {
            id: 4,
            name: 'Dr. Robert Johnson',
            email: 'rjohnson@research.org',
            role: 'researcher',
            school: 'bfis',
            joinedDate: '2024-08-15',
            lastActive: '2024-11-10',
            apiKeysCount: 3
        },
        {
            id: 5,
            name: 'Sarah Martinez',
            email: 'smartinez@mentor.com',
            role: 'mentor',
            school: 'bfis',
            joinedDate: '2024-07-20',
            lastActive: '2024-11-12',
            apiKeysCount: 1
        }
    ],

    // API Keys with different permission levels
    apiKeys: [
        {
            id: 1,
            key: 'sk_bfis_ADM_a7f3k9m2p1q8r5t6',
            name: 'Admin Master Key',
            role: 'admin',
            permissions: ['read', 'write', 'delete', 'manage_users', 'manage_settings'],
            createdBy: 'Maria Garcia',
            createdDate: '2024-06-15',
            lastUsed: '2024-11-15',
            status: 'active',
            usageCount: 1247
        },
        {
            id: 2,
            key: 'sk_bfis_TCH_b9g5j2n7p4s1v8x3',
            name: 'Teacher Dashboard Access',
            role: 'teacher',
            permissions: ['read', 'write_comments', 'export_data'],
            createdBy: 'Maria Garcia',
            createdDate: '2024-07-01',
            lastUsed: '2024-11-14',
            status: 'active',
            usageCount: 532
        },
        {
            id: 3,
            key: 'sk_bfis_RES_c4h8k1m6q3t9w2y7',
            name: 'Research API - Full Read Access',
            role: 'researcher',
            permissions: ['read', 'export_data', 'historical_data'],
            createdBy: 'Maria Garcia',
            createdDate: '2024-08-15',
            lastUsed: '2024-11-10',
            status: 'active',
            usageCount: 3421
        },
        {
            id: 4,
            key: 'sk_bfis_RES_d8j3l7n2r5u1x6z9',
            name: 'Research API - Limited',
            role: 'researcher',
            permissions: ['read'],
            createdBy: 'Dr. Robert Johnson',
            createdDate: '2024-10-01',
            lastUsed: '2024-11-09',
            status: 'active',
            usageCount: 145
        },
        {
            id: 5,
            key: 'sk_bfis_MNT_e2f9h4k8m1p7s3v6',
            name: 'Mentor Read Access',
            role: 'mentor',
            permissions: ['read', 'view_students'],
            createdBy: 'Sarah Martinez',
            createdDate: '2024-07-20',
            lastUsed: '2024-11-12',
            status: 'active',
            usageCount: 87
        },
        {
            id: 6,
            key: 'sk_bfis_ADM_f7g2j6l9n3q8t1w5',
            name: 'Backup Admin Key',
            role: 'admin',
            permissions: ['read', 'write', 'delete', 'manage_users', 'manage_settings'],
            createdBy: 'Maria Garcia',
            createdDate: '2024-06-20',
            lastUsed: null,
            status: 'inactive',
            usageCount: 0
        }
    ],

    // Thresholds and alert configurations
    thresholds: [
        {
            id: 1,
            parameter: 'co2',
            value: 1000,
            unit: 'ppm',
            condition: 'above',
            action: 'alert',
            actionDetails: 'Send notification to teachers',
            severity: 'warning',
            enabled: true
        },
        {
            id: 2,
            parameter: 'co2',
            value: 1500,
            unit: 'ppm',
            condition: 'above',
            action: 'alert',
            actionDetails: 'Send urgent notification + automatic ventilation recommendation',
            severity: 'critical',
            enabled: true
        },
        {
            id: 3,
            parameter: 'temperature',
            value: 26,
            unit: '°C',
            condition: 'above',
            action: 'alert',
            actionDetails: 'Suggest cooling measures',
            severity: 'info',
            enabled: true
        },
        {
            id: 4,
            parameter: 'humidity',
            value: 70,
            unit: '%',
            condition: 'above',
            action: 'log',
            actionDetails: 'Log event for analysis',
            severity: 'info',
            enabled: true
        },
        {
            id: 5,
            parameter: 'humidity',
            value: 30,
            unit: '%',
            condition: 'below',
            action: 'alert',
            actionDetails: 'Humidity too low - consider humidifier',
            severity: 'warning',
            enabled: false
        }
    ],

    // Recent sensor data for graphs
    sensorData: {
        // Last 24 hours of CO2 data
        co2: Array.from({ length: 24 }, (_, i) => ({
            timestamp: new Date(Date.now() - (23 - i) * 3600000).toISOString(),
            value: 400 + Math.random() * 800 + (i > 8 && i < 16 ? 400 : 0), // Higher during school hours
            location: 'Classroom 3B'
        })),
        // Temperature data
        temperature: Array.from({ length: 24 }, (_, i) => ({
            timestamp: new Date(Date.now() - (23 - i) * 3600000).toISOString(),
            value: 20 + Math.random() * 5,
            location: 'Classroom 3B'
        })),
        // Humidity data
        humidity: Array.from({ length: 24 }, (_, i) => ({
            timestamp: new Date(Date.now() - (23 - i) * 3600000).toISOString(),
            value: 45 + Math.random() * 20,
            location: 'Classroom 3B'
        }))
    },

    // Role definitions
    roleDefinitions: {
        admin: {
            name: 'Administrator',
            description: 'Full access to all portal features',
            color: '#dc2626',
            permissions: ['read', 'write', 'delete', 'manage_users', 'manage_settings', 'manage_api_keys', 'configure_thresholds']
        },
        teacher: {
            name: 'Teacher',
            description: 'View data, manage classroom settings',
            color: '#2563eb',
            permissions: ['read', 'write_comments', 'export_data', 'view_students']
        },
        student: {
            name: 'Student',
            description: 'View assigned data and participate in projects',
            color: '#16a34a',
            permissions: ['read', 'view_own_data']
        },
        researcher: {
            name: 'Researcher',
            description: 'Access to data for academic research',
            color: '#9333ea',
            permissions: ['read', 'export_data', 'historical_data']
        },
        mentor: {
            name: 'Project Mentor',
            description: 'Guide students and view project progress',
            color: '#ea580c',
            permissions: ['read', 'view_students', 'add_comments']
        }
    }
};

// Export for use in portal
window.MockData = MockData;
