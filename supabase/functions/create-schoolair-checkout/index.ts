import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts'
import { createSupabaseAdmin } from '../_shared/supabase.ts'
import { createLogger } from '../_shared/log.ts'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const log = createLogger('create-schoolair-checkout')

const PRICES: Record<string, number> = {
  home_build: 9500,  // €95 in cents
  installed: 12500,  // €125 in cents
}

serve(async (req) => {
  const corsResp = handleCors(req); if (corsResp) return corsResp;

  try {
    const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
      apiVersion: '2023-10-16',
      httpClient: Stripe.createFetchHttpClient(),
    })
    const supabase = createSupabaseAdmin()

    const body = await req.json()
    const { type, kit_type, tier, email, display_name, dedication, success_url, cancel_url } = body

    // Validate
    if (!email) throw new Error('Email is required')
    if (type === 'sponsor' && !kit_type) throw new Error('kit_type required for sponsors')
    if (type === 'patron' && !tier) throw new Error('tier required for patrons')
    if (type === 'sponsor' && !PRICES[kit_type]) throw new Error('Invalid kit_type')
    if (type === 'patron' && ![5, 10, 25].includes(tier)) throw new Error('Invalid tier')

    const amount = type === 'sponsor' ? PRICES[kit_type] : tier * 100

    // Insert pending sponsor row
    const { data: sponsor, error: dbError } = await supabase
      .from('schoolair_sponsors')
      .insert({
        email,
        display_name: display_name || null,
        dedication: dedication || null,
        sponsor_type: type,
        kit_type: type === 'sponsor' ? kit_type : null,
        tier: type === 'patron' ? tier : null,
        amount,
      })
      .select('id, label_token')
      .single()

    if (dbError) throw new Error('Failed to create sponsor record: ' + dbError.message)

    // Get or create Stripe Customer by email
    const existing = await stripe.customers.list({ email, limit: 1 })
    let stripeCustomerId: string
    if (existing.data.length > 0) {
      stripeCustomerId = existing.data[0].id
    } else {
      const customer = await stripe.customers.create({
        email,
        metadata: { source: 'schoolair', display_name: display_name || '' },
      })
      stripeCustomerId = customer.id
    }

    const metadata = {
      payment_type: type === 'sponsor' ? 'schoolair_sponsor' : 'schoolair_patron',
      sponsor_id: sponsor.id,
      sponsor_type: type,
      kit_type: kit_type || '',
      tier: tier?.toString() || '',
      display_name: display_name || '',
      dedication: dedication || '',
      customer_email: email,
    }

    let session: Stripe.Checkout.Session

    if (type === 'sponsor') {
      session = await stripe.checkout.sessions.create({
        customer: stripeCustomerId,
        payment_method_types: ['card'],
        mode: 'payment',
        line_items: [{
          price_data: {
            currency: 'eur',
            product_data: {
              name: kit_type === 'installed'
                ? 'SchoolAIR Installed Kit'
                : 'SchoolAIR Home Build Kit',
              description: kit_type === 'installed'
                ? 'Fully assembled and installed air quality monitor for one classroom'
                : 'DIY air quality monitor kit — build it with your kids!',
            },
            unit_amount: amount,
          },
          quantity: 1,
        }],
        metadata,
        payment_intent_data: { metadata },
        success_url,
        cancel_url,
      })
    } else {
      session = await stripe.checkout.sessions.create({
        customer: stripeCustomerId,
        payment_method_types: ['card'],
        mode: 'subscription',
        line_items: [{
          price_data: {
            currency: 'eur',
            product_data: {
              name: `SchoolAIR Monthly Patron — €${tier}/mo`,
              description: 'Monthly contribution to SchoolAIR air quality monitoring',
            },
            unit_amount: amount,
            recurring: { interval: 'month' },
          },
          quantity: 1,
        }],
        subscription_data: { metadata },
        metadata,
        success_url,
        cancel_url,
      })
    }

    // Update sponsor row with session ID
    await supabase
      .from('schoolair_sponsors')
      .update({ stripe_session_id: session.id })
      .eq('id', sponsor.id)

    return jsonResponse({ success: true, url: session.url })
  } catch (error) {
    log.error('Checkout error:', error)
    return errorResponse(error.message || 'Failed to create checkout', 500)
  }
})
