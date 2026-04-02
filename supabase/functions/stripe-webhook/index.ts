import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import Stripe from 'https://esm.sh/stripe@14.21.0'
import { handleCors, corsHeaders, jsonResponse } from '../_shared/cors.ts'
import { createSupabaseAdmin } from '../_shared/supabase.ts'
import { sendEmail } from '../_shared/email.ts'
import { createLogger } from '../_shared/log.ts'

const log = createLogger('stripe-webhook')

serve(async (req) => {
  const corsResponse = handleCors(req)
  if (corsResponse) return corsResponse

  try {
    const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
      apiVersion: '2023-10-16',
      httpClient: Stripe.createFetchHttpClient(),
    })
    const supabase = createSupabaseAdmin()

    // Verify signature
    const body = await req.text()
    const signature = req.headers.get('stripe-signature')
    if (!signature) return new Response(JSON.stringify({ error: 'No signature' }), { status: 400, headers: corsHeaders })

    let event: Stripe.Event
    try {
      event = stripe.webhooks.constructEvent(body, signature, Deno.env.get('STRIPE_WEBHOOK_SECRET')!)
    } catch (err) {
      log.error('Signature verification failed:', err)
      return new Response(JSON.stringify({ error: 'Invalid signature' }), { status: 400, headers: corsHeaders })
    }

    // Process asynchronously, return 200 immediately
    const processEvent = async () => {
      try {
        if (event.type === 'checkout.session.completed') {
          const session = event.data.object as Stripe.Checkout.Session
          const metadata = session.metadata || {}

          if (metadata.payment_type === 'schoolair_sponsor') {
            await processSponsorPayment(supabase, session, metadata)
          } else if (metadata.payment_type === 'schoolair_patron') {
            await processPatronPayment(supabase, session, metadata)
          }
        } else if (event.type === 'customer.subscription.deleted') {
          const subscription = event.data.object as Stripe.Subscription
          const metadata = subscription.metadata || {}
          if (metadata.payment_type === 'schoolair_patron') {
            await supabase
              .from('schoolair_sponsors')
              .update({ status: 'cancelled', updated_at: new Date().toISOString() })
              .eq('id', metadata.sponsor_id)
            log.info('Patron subscription cancelled:', metadata.sponsor_id)
          }
        }
      } catch (err) {
        log.error('Error processing event:', err)
      }
    }

    // Fire and forget
    processEvent()

    return jsonResponse({ received: true })
  } catch (error) {
    log.error('Webhook error:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: corsHeaders })
  }
})

async function processSponsorPayment(supabase: any, session: any, metadata: any) {
  const sponsorId = metadata.sponsor_id

  const { data: sponsor } = await supabase
    .from('schoolair_sponsors')
    .update({
      status: 'completed',
      stripe_payment_id: session.payment_intent as string,
      updated_at: new Date().toISOString(),
    })
    .eq('id', sponsorId)
    .select('*')
    .single()

  if (!sponsor) {
    log.error('Sponsor not found:', sponsorId)
    return
  }

  log.info('Sponsor payment completed:', sponsorId)

  const kitLabel = sponsor.kit_type === 'exterior' ? 'Exterior Unit' : 'Interior Unit'
  const editUrl = `https://bfis.schoolair.org/portal/sponsor.html?edit=${sponsor.label_token}`

  // Notify admin
  await sendEmail({
    to: 'info@alellagreentech.com',
    subject: `New SchoolAIR Sponsorship: ${kitLabel} by ${sponsor.display_name || sponsor.email}`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: #2e7d32;">New Unit Sponsorship!</h2>
        <table style="width: 100%; border-collapse: collapse;">
          <tr><td style="padding: 8px 0; font-weight: bold;">Type:</td><td>${kitLabel}</td></tr>
          <tr><td style="padding: 8px 0; font-weight: bold;">Amount:</td><td>&euro;${(sponsor.amount / 100).toFixed(0)}</td></tr>
          <tr><td style="padding: 8px 0; font-weight: bold;">Sponsor:</td><td>${sponsor.display_name || 'Anonymous'}</td></tr>
          <tr><td style="padding: 8px 0; font-weight: bold;">Email:</td><td>${sponsor.email}</td></tr>
          ${sponsor.dedication ? `<tr><td style="padding: 8px 0; font-weight: bold;">Details:</td><td>${sponsor.dedication}</td></tr>` : ''}
        </table>
      </div>
    `,
    tags: [{ name: 'type', value: 'schoolair_admin_notification' }],
  })

  // Thank the sponsor
  await sendEmail({
    to: sponsor.email,
    subject: 'Thank you for sponsoring a SchoolAIR classroom!',
    html: `
      <div style="font-family: 'Inter', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background: linear-gradient(135deg, #2e7d32, #4caf50); padding: 2rem; text-align: center; border-radius: 12px 12px 0 0;">
          <h1 style="color: white; margin: 0;">Thank You!</h1>
          <p style="color: rgba(255,255,255,0.9); margin-top: 0.5rem;">You're helping protect a classroom</p>
        </div>
        <div style="background: white; padding: 2rem; border: 1px solid #e2e8f0; border-radius: 0 0 12px 12px;">
          <p>Dear ${sponsor.display_name || 'Sponsor'},</p>
          <p>Thank you for sponsoring a <strong>${kitLabel}</strong> (&euro;${(sponsor.amount / 100).toFixed(0)})!</p>
          ${sponsor.dedication ? `<p>Your dedication: <em>"${sponsor.dedication}"</em></p>` : ''}

          <div style="background: #f0fdf4; border-left: 4px solid #2e7d32; padding: 1rem 1.5rem; margin: 1.5rem 0; border-radius: 4px;">
            <strong>Your display label</strong><br>
            <p style="margin: 0.5rem 0;">A plaque will be placed in the classroom with your chosen label. Currently set to:</p>
            <p style="font-size: 1.1rem; font-weight: 600; color: #1e293b;">
              "${sponsor.display_name || 'Anonymous Sponsor'}"
            </p>
            <p><a href="${editUrl}" style="color: #2e7d32; font-weight: 500;">Click here to update your display name</a></p>
          </div>

          <p>The SchoolAIR team will be in touch about installation. Every sensor makes a difference!</p>
          <p style="color: #64748b; font-size: 0.9rem; margin-top: 2rem;">&mdash; The SchoolAIR Team</p>
        </div>
      </div>
    `,
    tags: [{ name: 'type', value: 'schoolair_sponsor_thankyou' }],
  })
}

async function processPatronPayment(supabase: any, session: any, metadata: any) {
  const sponsorId = metadata.sponsor_id
  const subscriptionId = session.subscription as string

  const { data: sponsor } = await supabase
    .from('schoolair_sponsors')
    .update({
      status: 'completed',
      stripe_payment_id: subscriptionId || session.payment_intent,
      updated_at: new Date().toISOString(),
    })
    .eq('id', sponsorId)
    .select('*')
    .single()

  if (!sponsor) {
    log.error('Patron not found:', sponsorId)
    return
  }

  log.info('Patron subscription started:', sponsorId)

  const editUrl = `https://bfis.schoolair.org/portal/sponsor.html?edit=${sponsor.label_token}`

  // Notify admin
  await sendEmail({
    to: 'info@alellagreentech.com',
    subject: `New SchoolAIR Patron: ${sponsor.display_name || sponsor.email} at \u20ac${sponsor.tier}/mo`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: #1e3a8a;">New Monthly Patron!</h2>
        <table style="width: 100%; border-collapse: collapse;">
          <tr><td style="padding: 8px 0; font-weight: bold;">Tier:</td><td>&euro;${sponsor.tier}/month</td></tr>
          <tr><td style="padding: 8px 0; font-weight: bold;">Patron:</td><td>${sponsor.display_name || 'Anonymous'}</td></tr>
          <tr><td style="padding: 8px 0; font-weight: bold;">Email:</td><td>${sponsor.email}</td></tr>
        </table>
      </div>
    `,
    tags: [{ name: 'type', value: 'schoolair_admin_notification' }],
  })

  // Welcome the patron
  await sendEmail({
    to: sponsor.email,
    subject: 'Welcome, SchoolAIR Patron!',
    html: `
      <div style="font-family: 'Inter', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background: linear-gradient(135deg, #1e3a8a, #3b82f6); padding: 2rem; text-align: center; border-radius: 12px 12px 0 0;">
          <h1 style="color: white; margin: 0;">Welcome, Patron!</h1>
          <p style="color: rgba(255,255,255,0.9); margin-top: 0.5rem;">Your ongoing support makes a real difference</p>
        </div>
        <div style="background: white; padding: 2rem; border: 1px solid #e2e8f0; border-radius: 0 0 12px 12px;">
          <p>Dear ${sponsor.display_name || 'Patron'},</p>
          <p>Thank you for becoming a <strong>SchoolAIR Monthly Patron</strong> at <strong>&euro;${sponsor.tier}/month</strong>!</p>
          <p>Your contribution helps fund ongoing maintenance, calibration, and expansion of air quality monitoring at Benjamin Franklin International School.</p>

          <div style="background: #eff6ff; border-left: 4px solid #1e3a8a; padding: 1rem 1.5rem; margin: 1.5rem 0; border-radius: 4px;">
            <strong>Your display name on the Sponsors Wall</strong><br>
            <p style="font-size: 1.1rem; font-weight: 600; color: #1e293b;">
              "${sponsor.display_name || 'Anonymous Patron'}"
            </p>
            <p><a href="${editUrl}" style="color: #1e3a8a; font-weight: 500;">Click here to update your display name</a></p>
          </div>

          <p style="color: #64748b; font-size: 0.9rem; margin-top: 2rem;">&mdash; The SchoolAIR Team</p>
        </div>
      </div>
    `,
    tags: [{ name: 'type', value: 'schoolair_patron_welcome' }],
  })
}
