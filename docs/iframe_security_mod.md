# iframe Security Modification

## Problem

The air-school dashboard (`/air-school/index.html`) embedded the live data dashboard from `data.schoolair.org` via an iframe with the API token visible in the URL:

```html
<iframe src="https://data.schoolair.org/node/admin-dashboard?token=BFISSecretToken">
```

Anyone inspecting the page source could copy the token and access the sensor data API directly.

## Solution

A Supabase Edge Function (`get-sensor-data`) now acts as a server-side proxy between the frontend and `data.schoolair.org`. The token is stored only in the Edge Function — it never reaches the browser.

### Architecture

```
Browser (no token)
  → /air-school/live-dashboard.html
    → fetch('supabase.co/functions/v1/get-sensor-data')
      → Edge Function adds Bearer token server-side
        → data.schoolair.org/node/aqc/apiv1/read
          → returns sensor data
        ← JSON response
      ← proxied to browser
    ← Chart.js renders data
```

### Files Changed

| File | Change |
|------|--------|
| `air-school/index.html` | iframe now loads `live-dashboard.html` instead of `data.schoolair.org?token=...` |
| `air-school/live-dashboard.html` | New — standalone dashboard that fetches via proxy, renders with Chart.js |
| `supabase/functions/get-sensor-data/index.ts` | New — proxy Edge Function with 30s cache |

### How the Proxy Works

- **Endpoint:** `https://gzbuvywxrzcovqohmbol.supabase.co/functions/v1/get-sensor-data`
- **Auth:** No auth required from the browser (JWT verification disabled)
- **Upstream:** Fetches from `data.schoolair.org/node/aqc/apiv1/read` with `Bearer BFISSecretToken`
- **Caching:** Responses cached for 30 seconds to reduce upstream load
- **CORS:** Allows requests from any origin (`*`)

### Dashboard Features

`live-dashboard.html` provides:
- Metric selector buttons (PM2.5, CO2, Temperature, Humidity, PM1.0, PM10.0, CO, NO2, VOC)
- Time-series Chart.js line chart
- Data table (latest 50 readings)
- Safety alerts with threshold indicators
- Auto-refresh every 30 seconds

### Deployment

The Edge Function is deployed to the SchoolAir Supabase project:

```bash
supabase functions deploy get-sensor-data --project-ref gzbuvywxrzcovqohmbol --no-verify-jwt
```

### Token Rotation

If the `data.schoolair.org` token needs to be changed, update it in the Edge Function source (`supabase/functions/get-sensor-data/index.ts`) and redeploy. No frontend changes required.
