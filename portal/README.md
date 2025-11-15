# SchoolAIR School Portal System

## Overview

The School Portal System allows each participating school to have their own subdomain (e.g., `bfis.schoolair.org`) with a comprehensive management portal for:

1. **Custom Cover Artwork** - Display school branding and identity with key statistics
2. **Data Reports & AQI Dashboard** - Real-time air quality monitoring with visual indicators, interactive charts, and data export
3. **User & API Key Management** - Manage students, teachers, researchers, and mentors with role-based access
4. **Dashboard Configuration** - Set thresholds and automated actions for air quality parameters

## Architecture

### Tech Stack
- **Frontend**: Vanilla JavaScript, HTML5, CSS3
- **Backend**: Supabase (PostgreSQL database, Authentication, Storage, APIs)
- **Hosting**: Static hosting with wildcard DNS subdomain support
- **Charts**: Chart.js for data visualization

### Subdomain Routing
- Manual DNS configuration in SiteGround (CNAME records for each school)
- Client-side detection of subdomain in JavaScript
- School configuration loaded from Supabase (currently mock data)
- Current schools: BFIS (Benjamin Franklin International School)

## File Structure

```
portal/
├── index.html              # Main portal page
├── css/
│   └── portal.css          # Portal styles
├── js/
│   ├── subdomain.js        # Subdomain detection utility
│   ├── mock-data.js        # Mock data for development
│   └── portal.js           # Main portal logic
└── README.md               # This file
```

## Features

### 1. Cover Art Section
- Customizable hero image with adjustable framing
- School name and location display
- Real-time statistics cards:
  - **Classrooms/Exteriors Protected**: Number of monitored locations (48 for BFIS)
  - **Students**: Active students in program (25 for BFIS)
  - **Data Points**: Total sensor readings collected (980K for BFIS)
  - **Alerts**: Current active alerts (1 for BFIS)
- Edit cover artwork button (admin only)

### 2. Data Reports & AQI Dashboard

**AQI Circular Indicators:**
- Four circular progress indicators with color-coded air quality status:
  - **Interior Today**: Current indoor air quality (AQI: 24 - Good)
  - **Interior This Week**: Weekly average indoor air quality (AQI: 28 - Good)
  - **Exterior Today**: Current outdoor air quality (AQI: 42 - Moderate)
  - **Exterior This Week**: Weekly average outdoor air quality (AQI: 45 - Moderate)
- Color-coded badges: Good (green), Moderate (orange), Poor (red)
- SVG-based circular progress visualization
- Real-time AQI calculation and display

**Interactive Charts:**
- CO₂ levels (ppm) with min/max/avg statistics
- Temperature (°C) trends
- Humidity (%) monitoring
- 24-hour historical data visualization
- Chart.js powered interactive graphs

**Report Controls:**
- Time period selection (24h, 7d, 30d, custom range)
- Data export functionality (CSV/Excel)
- Weekly summary with insights and recommendations

### 3. User & API Key Management

**User Roles:**
- **Admin**: Full portal access, manage users and settings
- **Teacher**: View data, manage classroom settings
- **Student**: View assigned data, participate in projects
- **Researcher**: Access data for academic research
- **Mentor**: Guide students, view project progress

**User Management:**
- Role-based filtering tabs
- User table with join date and last active tracking
- Edit, view API keys, and delete actions
- API key count per user

**API Key Features:**
- Role-based permissions (read data, write data, manage users, etc.)
- Usage tracking (API call count, last used timestamp)
- Create, regenerate, and revoke keys
- Granular permission control
- Status indicators (active/revoked)
- Copy-to-clipboard functionality

### 4. Dashboard Configuration

**Threshold Management:**
- Configure alert thresholds for:
  - CO₂ levels (ppm)
  - Temperature (°C)
  - Humidity (%)
  - Other air quality parameters

**Automated Actions:**
- Send alerts to specific user roles
- Log events for analysis
- Trigger automated recommendations
- Set severity levels (info, warning, critical)
- Enable/disable thresholds with toggle switches
- Edit and delete threshold configurations

## Testing

### Local Testing

1. Open `portal/index.html` in a browser
2. Add `?school=bfis` to the URL to simulate BFIS subdomain:
   ```
   file:///path/to/portal/index.html?school=bfis
   ```

### Testing with Local Server

```bash
# Using Python
python3 -m http.server 8000

# Then visit:
http://localhost:8000/portal/?school=bfis
```

### Testing on Production

**Current Live School:**
- BFIS: `https://bfis.schoolair.org/portal/`

**DNS Setup (SiteGround):**
1. Log into SiteGround DNS management
2. Add CNAME record for each school:
   - Type: CNAME
   - Name: [school-slug] (e.g., "bfis")
   - Points to: schoolair.org
   - TTL: 3600
3. Verify with `nslookup [school-slug].schoolair.org`
4. Access portal at `https://[school-slug].schoolair.org/portal/`

## Mock Data

Currently using mock data in `js/mock-data.js` for development. Includes:
- 5 sample users across all roles
- 6 API keys with different permission levels
- 5 threshold configurations
- 24 hours of simulated sensor data

## Integration with Supabase

### Database Schema

```sql
-- Schools table
CREATE TABLE schools (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    location TEXT,
    cover_image TEXT,
    logo TEXT,
    primary_color TEXT,
    secondary_color TEXT,
    description TEXT,
    joined_date DATE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'teacher', 'student', 'researcher', 'mentor')),
    school_id UUID REFERENCES schools(id),
    joined_date DATE DEFAULT CURRENT_DATE,
    last_active TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- API Keys table
CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    permissions JSONB,
    school_id UUID REFERENCES schools(id),
    created_by UUID REFERENCES users(id),
    created_date DATE DEFAULT CURRENT_DATE,
    last_used TIMESTAMP,
    status TEXT DEFAULT 'active',
    usage_count INTEGER DEFAULT 0
);

-- Thresholds table
CREATE TABLE thresholds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id UUID REFERENCES schools(id),
    parameter TEXT NOT NULL,
    value NUMERIC NOT NULL,
    unit TEXT NOT NULL,
    condition TEXT CHECK (condition IN ('above', 'below')),
    action TEXT NOT NULL,
    action_details TEXT,
    severity TEXT CHECK (severity IN ('info', 'warning', 'critical')),
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Sensor Data table
CREATE TABLE sensor_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id UUID REFERENCES schools(id),
    timestamp TIMESTAMP NOT NULL,
    co2 NUMERIC,
    temperature NUMERIC,
    humidity NUMERIC,
    location TEXT,
    sensor_id TEXT
);
```

### Connecting to Supabase

1. Update `js/subdomain.js` to fetch from Supabase:

```javascript
async loadSchoolConfig() {
    const { data, error } = await supabase
        .from('schools')
        .select('*')
        .eq('slug', this.schoolSlug)
        .single();

    if (error) {
        console.error('Error loading school:', error);
        return null;
    }

    this.config = data;
    return this.config;
}
```

2. Replace mock data queries in `js/portal.js` with Supabase queries

## Completed Features

- ✅ Subdomain-based school portals (bfis.schoolair.org)
- ✅ DNS configuration for BFIS
- ✅ Cover artwork section with custom image framing
- ✅ AQI dashboard with circular progress indicators
- ✅ Interactive Chart.js visualizations
- ✅ User and API key management UI
- ✅ Threshold configuration interface
- ✅ Mock data system for development
- ✅ Responsive design and styling

## Next Steps

1. **Supabase Integration**: Replace mock data with live database
   - Connect to schools, users, api_keys, thresholds, and sensor_data tables
   - Implement Row Level Security (RLS) policies
2. **Authentication**: Implement Supabase Auth for user login
   - Email/password authentication
   - Role-based access control
   - Session management
3. **File Upload**: Enable cover artwork upload to Supabase Storage
   - Image upload interface
   - Image optimization and resizing
   - Secure storage with access controls
4. **Real-time Updates**: Use Supabase realtime subscriptions for live data
   - Real-time sensor data updates
   - Live AQI calculations
   - Alert notifications
5. **API Integration**: Connect to actual sensor data streams
   - Integrate with hardware sensors
   - Data validation and processing
   - Historical data aggregation
6. **Additional Schools**: Add more schools to the system
   - Create DNS records
   - Configure school-specific settings
   - Customize branding per school

## Security Considerations

- Row Level Security (RLS) in Supabase to ensure schools only see their data
- API key authentication for external access
- Role-based permissions enforced at database level
- Secure HTTPS connections required
- Regular API key rotation

## Support

For questions or issues with the portal system:
- Email: info@schoolair.org
- GitHub: [SchoolAIR Repository]

---

## Current Status

**Development Stage**: Beta - Live with mock data
- **Live Portal**: https://bfis.schoolair.org/portal/
- **Data Source**: Mock data (js/mock-data.js)
- **Schools**: 1 (BFIS - Benjamin Franklin International School, Barcelona)
- **Next Milestone**: Supabase integration for live sensor data

## Screenshots

Portal sections include:
1. Cover artwork with school branding and statistics
2. AQI dashboard with circular indicators showing air quality
3. Interactive charts for CO₂, temperature, and humidity
4. User management with role-based access
5. API key management with permissions
6. Threshold configuration for automated alerts

## Contributing

To add a new school to the portal system:
1. Add DNS CNAME record in SiteGround
2. Add school configuration to `js/subdomain.js` mockSchools object
3. Test locally with `?school=[slug]` parameter
4. Deploy and verify at `https://[slug].schoolair.org/portal/`
