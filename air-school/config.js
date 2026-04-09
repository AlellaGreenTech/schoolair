/**
 * SchoolAir Device Configuration
 * Maps real sensor device IDs to simulation room cards.
 * To add a new sensor, just add a line to the devices object.
 */
const SCHOOL_CONFIG = {
    proxyUrl: 'https://gzbuvywxrzcovqohmbol.supabase.co/functions/v1/get-sensor-data',
    refreshInterval: 30000,  // 30s (matches proxy cache TTL)
    staleThreshold: 300000,  // 5 min — data older than this shows as stale
    devices: {
        'aqc-4': 'nursery',          // Football Field → Nursery card
        // As sensors are installed, add mappings:
        // 'aqc-5': 'primary-a',
        // 'aqc-6': 'primary-b',
        // 'aqc-7': 'secondary-a',
        // 'aqc-8': 'secondary-b',
    }
};
