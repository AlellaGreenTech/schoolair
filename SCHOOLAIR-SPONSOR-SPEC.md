# SchoolAir Sponsor & Patron System — Implementation Spec

> Transfer this file to your SchoolAir Claude Code window. It contains everything needed to implement the full sponsor/patron system with Stripe integration.

## Overview

Add a sponsorship system to the BFIS SchoolAir portal so parents/community can fund air quality monitor kits. Two models:
- **Sponsor** = one-time kit purchase (Home Build €65, Installed €95)
- **Patron** = recurring monthly donation (€5/€10/€25 tiers)

SchoolAir gets **its own Supabase project** with its own Edge Functions. It connects to the **same Stripe account** as guidal.org (same bank destination).

---

## Architecture

```
schoolair.org (frontend)
  ├── portal/index.html          ← add CTA banner
  ├── portal/sponsor.html        ← NEW: sponsor page
  ├── portal/css/sponsor.css     ← NEW: styles
  └── portal/js/sponsor.js       ← NEW: checkout logic

SchoolAir Supabase project (backend — NEW project, separate from GUIDAL)
  ├── database
  │   └── schoolair_sponsors table
  │   └── get_schoolair_progress() RPC function
  ├── supabase/functions/_shared/
  │   ├── cors.ts
  │   ├── supabase.ts
  │   ├── email.ts
  │   └── log.ts
  └── supabase/functions/
      ├── create-schoolair-checkout/   ← creates Stripe Checkout Sessions
      ├── get-schoolair-sponsors/      ← public API for sponsors wall + progress
      ├── update-schoolair-label/      ← token-based label editing
      └── stripe-webhook/             ← handles payment confirmations
```

---

## Step 0: Set Up SchoolAir Supabase Project

1. Create a new Supabase project for SchoolAir (or use existing if one exists)
2. Set the following secrets on the Edge Functions:
   - `STRIPE_SECRET_KEY` — same key as GUIDAL (same Stripe account)
   - `STRIPE_WEBHOOK_SECRET` — NEW webhook secret (create a new webhook endpoint in Stripe Dashboard pointing to SchoolAir's Supabase URL)
   - `RESEND_API_KEY` — same as GUIDAL (or a new one if SchoolAir has its own Resend domain)
3. In Stripe Dashboard, create a new webhook endpoint:
   - URL: `https://<schoolair-supabase-ref>.supabase.co/functions/v1/stripe-webhook`
   - Events: `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.deleted`

---

## Step 1: Database Schema

### Table: `schoolair_sponsors`

```sql
CREATE TABLE schoolair_sponsors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ,
  email TEXT NOT NULL,
  display_name TEXT,                -- "Harry & Sally Brooks"
  dedication TEXT,                  -- "For Ms. Garcia's 3rd grade class"
  sponsor_type TEXT NOT NULL CHECK (sponsor_type IN ('sponsor', 'patron')),
  kit_type TEXT CHECK (kit_type IN ('home_build', 'installed')),  -- null for patrons
  tier INTEGER CHECK (tier IN (5, 10, 25)),                      -- null for sponsors
  amount INTEGER NOT NULL,          -- in cents (6500 = €65)
  currency TEXT NOT NULL DEFAULT 'eur',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled', 'refunded')),
  stripe_session_id TEXT,
  stripe_payment_id TEXT,           -- payment_intent for sponsors, subscription_id for patrons
  label_confirmed BOOLEAN NOT NULL DEFAULT false,
  label_token UUID DEFAULT gen_random_uuid()  -- secret token for edit-label URL
);

-- For the sponsors wall query
CREATE INDEX idx_schoolair_sponsors_wall ON schoolair_sponsors (status, created_at DESC);

-- For label edit lookups
CREATE INDEX idx_schoolair_sponsors_token ON schoolair_sponsors (label_token);

-- RLS
ALTER TABLE schoolair_sponsors ENABLE ROW LEVEL SECURITY;

-- Public can read completed sponsors (for the wall)
CREATE POLICY "Public can read completed sponsors"
  ON schoolair_sponsors FOR SELECT
  USING (status = 'completed');

-- Service role bypasses RLS automatically (used by Edge Functions)
```

### RPC Function: `get_schoolair_progress`

```sql
CREATE OR REPLACE FUNCTION get_schoolair_progress()
RETURNS JSON AS $$
  SELECT json_build_object(
    'protected', (
      SELECT COUNT(*)::int
      FROM schoolair_sponsors
      WHERE status = 'completed' AND sponsor_type = 'sponsor'
    ) + 2,  -- 2 existing sensors already installed
    'total', 48
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;
```

---

## Step 2: Shared Utilities

Copy these patterns from GUIDAL. Each file goes in `supabase/functions/_shared/`.

### `_shared/cors.ts`
```typescript
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
}

export function handleCors(req: Request): Response | null {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  return null
}

export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

export function errorResponse(message: string, status = 400): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
```

### `_shared/supabase.ts`
```typescript
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export function createSupabaseAdmin(): SupabaseClient {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const supabaseServiceKey =
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ??
    Deno.env.get('SERVICE_ROLE_KEY') ?? ''

  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
}
```

### `_shared/email.ts`
```typescript
const RESEND_API_URL = 'https://api.resend.com/emails'
// NOTE: Update FROM_EMAIL once SchoolAir has its own Resend domain
// For now, use GUIDAL's domain or a generic one
const FROM_EMAIL = 'SchoolAIR <noreply@guidal.org>'

interface EmailOptions {
  to: string | string[]
  subject: string
  html: string
  from?: string
  replyTo?: string
  tags?: { name: string; value: string }[]
}

interface EmailResult {
  success: boolean
  id?: string
  error?: string
}

export async function sendEmail(options: EmailOptions): Promise<EmailResult> {
  const apiKey = Deno.env.get('RESEND_API_KEY') ?? ''
  if (!apiKey) return { success: false, error: 'RESEND_API_KEY not configured' }

  const recipients = Array.isArray(options.to) ? options.to : [options.to]

  try {
    const response = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        from: options.from ?? FROM_EMAIL,
        to: recipients,
        subject: options.subject,
        html: options.html,
        ...(options.replyTo && { reply_to: options.replyTo }),
        ...(options.tags && { tags: options.tags }),
      }),
    })

    const data = await response.json()
    if (!response.ok) {
      console.error('Resend API error:', data)
      return { success: false, error: data.message || 'Email send failed' }
    }
    return { success: true, id: data.id }
  } catch (error) {
    console.error('Email sending error:', error)
    return { success: false, error: error.message }
  }
}
```

### `_shared/log.ts`
```typescript
export function createLogger(fn: string) {
  function toEntry(level: string, args: unknown[]): string {
    const msg = typeof args[0] === 'string' ? args[0] : ''
    const rest = typeof args[0] === 'string' ? args.slice(1) : args
    const entry: Record<string, unknown> = { level, fn, msg, ts: Date.now() }
    if (rest.length === 1) {
      const val = rest[0]
      entry.detail = val instanceof Error ? val.message : val
    } else if (rest.length > 1) {
      entry.detail = rest.map(v => v instanceof Error ? v.message : v)
    }
    return JSON.stringify(entry)
  }

  return {
    error(...args: unknown[]) { console.error(toEntry('error', args)) },
    warn(...args: unknown[]) { console.warn(toEntry('warn', args)) },
    info(...args: unknown[]) { console.log(toEntry('info', args)) },
  }
}
```

---

## Step 3: Edge Function — `create-schoolair-checkout`

File: `supabase/functions/create-schoolair-checkout/index.ts`

### Request
```
POST /functions/v1/create-schoolair-checkout
Content-Type: application/json

{
  "type": "sponsor" | "patron",
  "kit_type": "home_build" | "installed",   // required if type=sponsor
  "tier": 5 | 10 | 25,                     // required if type=patron
  "email": "parent@example.com",            // required
  "display_name": "Harry & Sally Brooks",   // optional
  "dedication": "For Ms. Garcia's class",   // optional
  "success_url": "https://bfis.schoolair.org/portal/sponsor.html?success=true",
  "cancel_url": "https://bfis.schoolair.org/portal/sponsor.html?cancelled=true"
}
```

### Response
```json
{ "success": true, "url": "https://checkout.stripe.com/..." }
```

### Logic
```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts'
import { createSupabaseAdmin } from '../_shared/supabase.ts'
import { createLogger } from '../_shared/log.ts'
import Stripe from 'https://esm.sh/stripe@14.21.0'

const log = createLogger('create-schoolair-checkout')

const PRICES = {
  home_build: 6500,  // €65 in cents
  installed: 9500,   // €95 in cents
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
      // One-time payment
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
      // Subscription (recurring patron)
      // Create price on the fly (Stripe deduplicates by lookup_key)
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
```

---

## Step 4: Edge Function — `stripe-webhook`

File: `supabase/functions/stripe-webhook/index.ts`

This is SchoolAir's own webhook (simpler than GUIDAL's — only handles 2 payment types).

### Key Pattern (from GUIDAL)
```typescript
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

async function processSponsorPayment(supabase, session, metadata) {
  const sponsorId = metadata.sponsor_id

  // Update to completed
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

  // Send thank-you email
  const kitLabel = sponsor.kit_type === 'installed' ? 'Installed Kit' : 'Home Build Kit'
  const editUrl = `https://bfis.schoolair.org/portal/sponsor.html?edit=${sponsor.label_token}`

  await sendEmail({
    to: sponsor.email,
    subject: 'Thank you for sponsoring a SchoolAIR classroom!',
    html: `
      <div style="font-family: 'Inter', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background: linear-gradient(135deg, #2e7d32, #4caf50); padding: 2rem; text-align: center; border-radius: 12px 12px 0 0;">
          <h1 style="color: white; margin: 0;">Thank You! 🎉</h1>
          <p style="color: rgba(255,255,255,0.9); margin-top: 0.5rem;">You're helping protect a classroom</p>
        </div>
        <div style="background: white; padding: 2rem; border: 1px solid #e2e8f0; border-radius: 0 0 12px 12px;">
          <p>Dear ${sponsor.display_name || 'Sponsor'},</p>
          <p>Thank you for sponsoring a <strong>${kitLabel}</strong> (€${(sponsor.amount / 100).toFixed(0)}) for Benjamin Franklin International School!</p>
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
          <p style="color: #64748b; font-size: 0.9rem; margin-top: 2rem;">— The SchoolAIR Team</p>
        </div>
      </div>
    `,
    tags: [{ name: 'type', value: 'schoolair_sponsor_thankyou' }],
  })
}

async function processPatronPayment(supabase, session, metadata) {
  const sponsorId = metadata.sponsor_id

  // For subscriptions, the subscription ID is in the session
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

  await sendEmail({
    to: sponsor.email,
    subject: 'Welcome, SchoolAIR Patron!',
    html: `
      <div style="font-family: 'Inter', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background: linear-gradient(135deg, #1e3a8a, #3b82f6); padding: 2rem; text-align: center; border-radius: 12px 12px 0 0;">
          <h1 style="color: white; margin: 0;">Welcome, Patron! 💙</h1>
          <p style="color: rgba(255,255,255,0.9); margin-top: 0.5rem;">Your ongoing support makes a real difference</p>
        </div>
        <div style="background: white; padding: 2rem; border: 1px solid #e2e8f0; border-radius: 0 0 12px 12px;">
          <p>Dear ${sponsor.display_name || 'Patron'},</p>
          <p>Thank you for becoming a <strong>SchoolAIR Monthly Patron</strong> at <strong>€${sponsor.tier}/month</strong>!</p>
          <p>Your contribution helps fund ongoing maintenance, calibration, and expansion of air quality monitoring at Benjamin Franklin International School.</p>

          <div style="background: #eff6ff; border-left: 4px solid #1e3a8a; padding: 1rem 1.5rem; margin: 1.5rem 0; border-radius: 4px;">
            <strong>Your display name on the Sponsors Wall</strong><br>
            <p style="font-size: 1.1rem; font-weight: 600; color: #1e293b;">
              "${sponsor.display_name || 'Anonymous Patron'}"
            </p>
            <p><a href="${editUrl}" style="color: #1e3a8a; font-weight: 500;">Click here to update your display name</a></p>
          </div>

          <p style="color: #64748b; font-size: 0.9rem; margin-top: 2rem;">— The SchoolAIR Team</p>
        </div>
      </div>
    `,
    tags: [{ name: 'type', value: 'schoolair_patron_welcome' }],
  })
}
```

---

## Step 5: Edge Function — `get-schoolair-sponsors`

File: `supabase/functions/get-schoolair-sponsors/index.ts`

```typescript
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
        'Cache-Control': 'public, max-age=60',  // Cache for 1 minute
      },
    })
  } catch (error) {
    return errorResponse(error.message || 'Failed to fetch sponsors', 500)
  }
})
```

---

## Step 6: Edge Function — `update-schoolair-label`

File: `supabase/functions/update-schoolair-label/index.ts`

```typescript
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
```

---

## Step 7: Frontend — CTA on Portal Homepage

Add this to `portal/index.html` after the "View Full Interactive Dashboard" block (after line 80, before `</section>`):

```html
<!-- Sponsor CTA -->
<div style="max-width: 800px; margin: 2rem auto; text-align: center;">
    <div style="background: linear-gradient(135deg, #2e7d32 0%, #1b5e20 100%); border-radius: 12px; padding: 2rem; box-shadow: 0 8px 16px rgba(0,0,0,0.15);">
        <div style="display: flex; align-items: center; justify-content: center; gap: 1rem; flex-wrap: wrap;">
            <div style="flex: 1; min-width: 250px; text-align: left; padding: 0 1rem;">
                <h3 style="color: white; margin: 0 0 0.5rem 0; font-size: 1.5rem; font-weight: 700;">
                    <i class="fas fa-heart" style="color: #ff6b6b;"></i> Protect a classroom!
                </h3>
                <p style="color: rgba(255,255,255,0.9); margin: 0; font-size: 1.05rem;">
                    Sponsor an air quality monitor — kits from just €65
                </p>
            </div>
            <a href="sponsor.html" style="display: inline-flex; align-items: center; gap: 0.5rem; background: white; color: #2e7d32; padding: 0.85rem 2rem; border-radius: 8px; text-decoration: none; font-weight: 700; font-size: 1.1rem; transition: transform 0.2s; white-space: nowrap;">
                <i class="fas fa-hand-holding-heart"></i>
                Become a Sponsor
            </a>
        </div>
    </div>
</div>
```

---

## Step 8: Frontend — Sponsor Page

### `portal/sponsor.html`

Full page with:
1. **Hero** — "Help Every Classroom Breathe Clean Air" + story text
2. **Progress bar** — visual "X of 48 classrooms protected"
3. **Sponsor cards** — Home Build €65, Installed €95 (with "Most Impact" badge)
4. **Patron cards** — €5/mo Supporter, €10/mo Champion, €25/mo Guardian
5. **Pre-checkout modal** — email (required), display name, dedication (optional)
6. **Sponsors wall** — grid of sponsor tiles with names/dedications
7. **Success/cancel banners** — shown on return from Stripe
8. **Label edit form** — shown when `?edit=TOKEN` in URL

### `portal/css/sponsor.css`

Key styles to create:
- `.sponsor-hero` — centered, max-width 800px, large heading
- `.progress-section` — progress bar container with green fill, percentage-based width
- `.sponsor-cards`, `.patron-cards` — CSS grid, auto-fit minmax(280px, 1fr)
- `.sponsor-card`, `.patron-card` — white, rounded, shadow, centered text, hover lift
- `.sponsor-card.featured` — green top border, "Most Impact" badge
- `.price` — large bold number, `/mo` in smaller text for patrons
- `.sponsors-wall` — grid of small tiles
- `.sponsor-tile` — light bg, rounded, name + dedication + type
- `.checkout-modal` — overlay + centered card, email/name/dedication fields
- `.success-banner`, `.cancel-banner` — top banner notifications
- Mobile responsive at 768px breakpoint

### `portal/js/sponsor.js`

Key functions:
```javascript
// Configuration — UPDATE THESE with SchoolAir's own Supabase project
const SUPABASE_URL = 'https://<schoolair-ref>.supabase.co'

document.addEventListener('DOMContentLoaded', async () => {
  await loadSponsorsWall()
  handleUrlParams()
})

async function loadSponsorsWall() {
  const resp = await fetch(`${SUPABASE_URL}/functions/v1/get-schoolair-sponsors`)
  const data = await resp.json()

  // Update progress bar
  const pct = (data.progress.protected / data.progress.total) * 100
  document.getElementById('progressBar').style.width = pct + '%'
  document.getElementById('progressCount').textContent = data.progress.protected

  // Render sponsor tiles
  const grid = document.getElementById('sponsorsGrid')
  if (data.sponsors.filter(s => s.display_name).length === 0) {
    grid.innerHTML = '<p class="empty-wall">Be the first to sponsor a classroom!</p>'
    return
  }
  grid.innerHTML = data.sponsors
    .filter(s => s.display_name)
    .map(s => `<div class="sponsor-tile">
      <strong>${escapeHtml(s.display_name)}</strong>
      ${s.dedication ? `<span class="tile-dedication">${escapeHtml(s.dedication)}</span>` : ''}
      <small class="tile-type">${formatType(s)}</small>
    </div>`).join('')
}

function formatType(s) {
  if (s.sponsor_type === 'patron') return `Monthly Patron · €${s.tier}/mo`
  return s.kit_type === 'installed' ? 'Installed Kit Sponsor' : 'Home Build Kit Sponsor'
}

function startCheckout(type, kitType, tier) {
  // Show modal with email + display name + dedication fields
  document.getElementById('checkoutModal').style.display = 'flex'
  document.getElementById('checkoutModal').dataset.type = type
  document.getElementById('checkoutModal').dataset.kitType = kitType || ''
  document.getElementById('checkoutModal').dataset.tier = tier || ''
}

async function submitCheckout() {
  const modal = document.getElementById('checkoutModal')
  const email = document.getElementById('checkoutEmail').value
  const displayName = document.getElementById('checkoutDisplayName').value
  const dedication = document.getElementById('checkoutDedication').value

  if (!email) { alert('Email is required'); return }

  const btn = document.getElementById('checkoutSubmitBtn')
  btn.disabled = true
  btn.textContent = 'Redirecting to payment...'

  try {
    const resp = await fetch(`${SUPABASE_URL}/functions/v1/create-schoolair-checkout`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        type: modal.dataset.type,
        kit_type: modal.dataset.kitType || undefined,
        tier: modal.dataset.tier ? parseInt(modal.dataset.tier) : undefined,
        email,
        display_name: displayName || undefined,
        dedication: dedication || undefined,
        success_url: window.location.origin + window.location.pathname + '?success=true',
        cancel_url: window.location.origin + window.location.pathname + '?cancelled=true',
      })
    })
    const data = await resp.json()
    if (data.url) {
      window.location.href = data.url
    } else {
      throw new Error(data.error || 'Failed to create checkout')
    }
  } catch (err) {
    alert('Error: ' + err.message)
    btn.disabled = false
    btn.textContent = 'Proceed to Payment'
  }
}

function handleUrlParams() {
  const params = new URLSearchParams(window.location.search)
  if (params.get('success')) {
    showBanner('success', 'Thank you for your sponsorship! Check your email for confirmation and a link to customize your display name.')
    window.history.replaceState({}, '', window.location.pathname)
  }
  if (params.get('cancelled')) {
    showBanner('cancel', 'Checkout was cancelled. No worries — you can try again anytime.')
    window.history.replaceState({}, '', window.location.pathname)
  }
  if (params.get('edit')) {
    showLabelEditor(params.get('edit'))
  }
}

function showLabelEditor(token) {
  // Hide main content, show label edit form
  document.querySelector('.sponsor-main-content').style.display = 'none'
  const editor = document.getElementById('labelEdit')
  editor.style.display = 'block'

  document.getElementById('labelForm').onsubmit = async (e) => {
    e.preventDefault()
    const resp = await fetch(`${SUPABASE_URL}/functions/v1/update-schoolair-label`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        token,
        display_name: document.getElementById('editDisplayName').value,
        dedication: document.getElementById('editDedication').value || undefined,
      })
    })
    if (resp.ok) {
      showBanner('success', 'Your display name has been updated!')
      setTimeout(() => window.location.href = 'sponsor.html', 2000)
    } else {
      alert('Failed to update. The link may have expired.')
    }
  }
}

function showBanner(type, message) {
  const banner = document.createElement('div')
  banner.className = `banner banner-${type}`
  banner.innerHTML = `<p>${message}</p><button onclick="this.parentElement.remove()">×</button>`
  document.body.prepend(banner)
}

function escapeHtml(str) {
  const div = document.createElement('div')
  div.textContent = str
  return div.innerHTML
}
```

---

## Step 9: Story Text for the Sponsor Page

Use this copy on the sponsor page:

> The SchoolAIR team has experimented widely with the latest tech components and has been able to greatly lower the cost of an air quality unit. The total cost of components in a kit is now about €50 — even with the best possible maker-level components selected. The housing and installation cost a little more, but the grand total is still surprisingly low. And each unit will forever protect a classroom by letting teachers know when it's time to ventilate — or shut a window due to poor outside air quality.

---

## Testing Checklist

- [ ] SchoolAir Supabase project created and linked
- [ ] Stripe webhook endpoint registered for SchoolAir's Supabase URL
- [ ] `schoolair_sponsors` table created
- [ ] All 4 Edge Functions deployed
- [ ] Secrets set: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `RESEND_API_KEY`
- [ ] Test one-time sponsor checkout (use card `4242 4242 4242 4242`)
- [ ] Test patron subscription checkout
- [ ] Verify webhook fires and updates DB row to `completed`
- [ ] Verify thank-you email arrives with label-edit link
- [ ] Verify label edit works via token URL
- [ ] Verify sponsors wall loads and displays completed sponsors
- [ ] Verify progress bar updates
- [ ] Test on mobile
- [ ] Test cancel flow (cancel in Stripe → banner shows)

---

## Stripe Dashboard Setup

In the **same Stripe account** as GUIDAL:

1. **New webhook endpoint**: `https://<schoolair-ref>.supabase.co/functions/v1/stripe-webhook`
   - Events: `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.deleted`
2. Copy the webhook signing secret → set as `STRIPE_WEBHOOK_SECRET` in SchoolAir's Supabase project
3. The `STRIPE_SECRET_KEY` is the same as GUIDAL's (same account, same destination)
