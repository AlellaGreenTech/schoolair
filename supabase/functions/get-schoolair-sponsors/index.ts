import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts'
import { createSupabaseAdmin } from '../_shared/supabase.ts'

serve(async (req) => {
  const corsResp = handleCors(req); if (corsResp) return corsResp;

  try {
    const supabase = createSupabaseAdmin()

    // Check for school_slug filter via query param
    const url = new URL(req.url)
    const schoolSlug = url.searchParams.get('school') || null

    // Get completed sponsors for the wall
    let query = supabase
      .from('schoolair_sponsors')
      .select('display_name, dedication, sponsor_type, kit_type, tier, created_at, school_slug')
      .eq('status', 'completed')
      .order('created_at', { ascending: false })

    if (schoolSlug) {
      query = query.eq('school_slug', schoolSlug)
    }

    const { data: sponsors, error: sponsorsError } = await query
    if (sponsorsError) throw new Error(sponsorsError.message)

    // Get progress count (filtered by school if specified)
    const { data: progress, error: progressError } = await supabase.rpc('get_schoolair_progress', {
      p_school_slug: schoolSlug
    })
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
