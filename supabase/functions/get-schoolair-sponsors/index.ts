import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts'
import { createSupabaseAdmin } from '../_shared/supabase.ts'

serve(async (req) => {
  const corsResp = handleCors(req); if (corsResp) return corsResp;

  try {
    const supabase = createSupabaseAdmin()

    // Get completed sponsors for the wall
    const { data: sponsors, error: sponsorsError } = await supabase
      .from('schoolair_sponsors')
      .select('display_name, dedication, sponsor_type, kit_type, tier, created_at')
      .eq('status', 'completed')
      .order('created_at', { ascending: false })

    if (sponsorsError) throw new Error(sponsorsError.message)

    // Get progress count
    const { data: progress, error: progressError } = await supabase.rpc('get_schoolair_progress')
    if (progressError) throw new Error(progressError.message)

    return new Response(JSON.stringify({ sponsors: sponsors || [], progress }), {
      status: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json',
        'Cache-Control': 'public, max-age=60',
      },
    })
  } catch (error) {
    return errorResponse(error.message || 'Failed to fetch sponsors', 500)
  }
})
