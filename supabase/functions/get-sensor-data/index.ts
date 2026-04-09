import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts'

const DATA_API_URL = 'https://data.schoolair.org/node/aqc/apiv1/read'
const DATA_API_TOKEN = 'BFISSecretToken'

let cache: { data: unknown; timestamp: number } | null = null
const CACHE_TTL = 30000 // 30 seconds

serve(async (req) => {
  const corsResp = handleCors(req); if (corsResp) return corsResp;

  try {
    // Return cached data if fresh
    if (cache && Date.now() - cache.timestamp < CACHE_TTL) {
      return jsonResponse(cache.data)
    }

    // Fetch from data.schoolair.org
    const resp = await fetch(DATA_API_URL, {
      headers: { 'Authorization': `Bearer ${DATA_API_TOKEN}` },
    })

    if (!resp.ok) {
      throw new Error(`Upstream API returned ${resp.status}`)
    }

    const data = await resp.json()

    // Cache the result
    cache = { data, timestamp: Date.now() }

    return jsonResponse(data)
  } catch (error) {
    return errorResponse(error.message || 'Failed to fetch sensor data', 502)
  }
})
