import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts'
import { createSupabaseAdmin } from '../_shared/supabase.ts'

serve(async (req) => {
  const corsResp = handleCors(req); if (corsResp) return corsResp;

  try {
    const supabase = createSupabaseAdmin()
    const { token, display_name, dedication } = await req.json()

    if (!token) throw new Error('Token is required')

    // Find sponsor by label_token
    const { data: sponsor, error: findError } = await supabase
      .from('schoolair_sponsors')
      .select('id')
      .eq('label_token', token)
      .single()

    if (findError || !sponsor) {
      return errorResponse('Invalid or expired token', 404)
    }

    // Update label
    const { error: updateError } = await supabase
      .from('schoolair_sponsors')
      .update({
        display_name: display_name || null,
        dedication: dedication || null,
        label_confirmed: true,
        updated_at: new Date().toISOString(),
      })
      .eq('id', sponsor.id)

    if (updateError) throw new Error(updateError.message)

    return jsonResponse({ success: true })
  } catch (error) {
    return errorResponse(error.message || 'Failed to update label', 500)
  }
})
