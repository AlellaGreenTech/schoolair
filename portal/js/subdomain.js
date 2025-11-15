/**
 * Subdomain Detection and School Configuration
 * Detects school subdomain and loads appropriate configuration
 */

class SchoolPortal {
    constructor() {
        this.schoolSlug = this.detectSchool();
        this.config = null;
    }

    /**
     * Detect school from subdomain
     * Examples:
     *   - bfis.schoolair.org → "bfis"
     *   - schoolair.org → null (main site)
     *   - localhost:8000 → null (development)
     */
    detectSchool() {
        const hostname = window.location.hostname;

        // Development/localhost
        if (hostname === 'localhost' || hostname === '127.0.0.1') {
            // Check for ?school= query parameter for testing
            const params = new URLSearchParams(window.location.search);
            return params.get('school');
        }

        // Production - extract subdomain
        const parts = hostname.split('.');

        // If it's just schoolair.org (2 parts), no subdomain
        if (parts.length <= 2) {
            return null;
        }

        // Extract subdomain (first part)
        const subdomain = parts[0];

        // Ignore www
        if (subdomain === 'www') {
            return null;
        }

        return subdomain;
    }

    /**
     * Load school configuration from Supabase or mock data
     */
    async loadSchoolConfig() {
        // For now, use mock data
        // Later: const { data } = await supabase.from('schools').select('*').eq('slug', this.schoolSlug)

        const mockSchools = {
            'bfis': {
                id: 1,
                slug: 'bfis',
                name: 'Benjamin Franklin International School',
                location: 'Barcelona, Spain',
                coverImage: '../images/students/working.jpg',
                logo: '../images/bfis-logo.png',
                primaryColor: '#1e3a8a',
                secondaryColor: '#3b82f6',
                description: 'Pioneering air quality monitoring in Barcelona',
                joinedDate: '2024-06',
                stats: {
                    sensors: 48,
                    students: 25,
                    dataPoints: 980000,
                    alerts: 1
                }
            }
        };

        this.config = mockSchools[this.schoolSlug] || null;
        return this.config;
    }

    /**
     * Check if we're on a school portal
     */
    isSchoolPortal() {
        return this.schoolSlug !== null;
    }

    /**
     * Redirect to main site if not a valid school
     */
    redirectToMain() {
        if (!this.isSchoolPortal()) {
            window.location.href = 'https://schoolair.org';
        }
    }
}

// Export for use in other scripts
window.SchoolPortal = SchoolPortal;
