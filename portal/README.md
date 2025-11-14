# SchoolAIR School Portal System

## Overview

The School Portal System allows each participating school to have their own subdomain (e.g., `bfis.schoolair.org`) with a comprehensive management portal for:

1. **Custom Cover Artwork** - Display school branding and identity
2. **User & API Key Management** - Manage students, teachers, researchers, and mentors with role-based access
3. **Dashboard Configuration** - Set thresholds and automated actions for air quality parameters
4. **Data Reports** - View and export curated air quality data in graphical format

## Architecture

### Tech Stack
- **Frontend**: Vanilla JavaScript, HTML5, CSS3
- **Backend**: Supabase (PostgreSQL database, Authentication, Storage, APIs)
- **Hosting**: Static hosting with wildcard DNS subdomain support
- **Charts**: Chart.js for data visualization

### Subdomain Routing
- Wildcard DNS: `*.schoolair.org` → static hosting
- Client-side detection of subdomain in JavaScript
- School configuration loaded from Supabase (currently mock data)

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
- Customizable hero image/gradient
- School name and location
- Key statistics dashboard (sensors, students, data points, alerts)
- Edit cover artwork button (admin only)

### 2. User & API Key Management

**User Roles:**
- **Admin**: Full portal access, manage users and settings
- **Teacher**: View data, manage classroom settings
- **Student**: View assigned data, participate in projects
- **Researcher**: Access data for academic research
- **Mentor**: Guide students, view project progress

**API Key Features:**
- Role-based permissions
- Usage tracking
- Create, regenerate, and revoke keys
- Granular permission control

### 3. Dashboard Configuration

Configure alert thresholds for:
- CO₂ levels (ppm)
- Temperature (°C)
- Humidity (%)
- Other air quality parameters

**Actions:**
- Send alerts to specific user roles
- Log events for analysis
- Trigger automated recommendations
- Set severity levels (info, warning, critical)

### 4. Data Reports
- Interactive charts (CO₂, temperature, humidity)
- Time period selection (24h, 7d, 30d, custom)
- Summary statistics and insights
- Data export functionality

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

### Testing on Staging/Production

1. Set up wildcard DNS: `*.schoolair.org` → your hosting
2. Visit: `https://bfis.schoolair.org/portal/`

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

## Next Steps

1. **DNS Setup**: Configure wildcard subdomain
2. **Supabase Integration**: Replace mock data with live database
3. **Authentication**: Implement Supabase Auth for user login
4. **File Upload**: Enable cover artwork upload to Supabase Storage
5. **Real-time Updates**: Use Supabase realtime subscriptions for live data
6. **API Integration**: Connect to actual sensor data streams

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

**Status**: Development with mock data
**Next Milestone**: Supabase integration and production deployment
