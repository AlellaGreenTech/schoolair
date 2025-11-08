# SchoolAIR Email Integration Setup

This guide explains how to deploy and configure the email contact form integration using Supabase Edge Functions and Resend.

## Overview

The contact form now uses:
- **Supabase Edge Functions** to handle email sending securely
- **Resend.com API** to send emails
- Multi-language support (EN, ES, CA, FR, IT)

## Prerequisites

1. **Supabase CLI** installed:
   ```bash
   brew install supabase/tap/supabase
   ```

2. **Supabase Project** already created:
   - Project URL: `https://gzbuvywxrzcovqohmbol.supabase.co`
   - Anon Key: Already configured in contact forms

3. **Resend API Key**: `re_aK7VyMyF_MTdDS2wdfr3vd7mAKZUtzFhr`

4. **Domain verification** in Resend for `schoolair.org` (required to send from `info@schoolair.org`)

## Step 1: Login to Supabase CLI

```bash
# Login to Supabase
supabase login

# Link to your project
supabase link --project-ref gzbuvywxrzcovqohmbol
```

## Step 2: Deploy the Edge Function

From the schoolair project directory:

```bash
# Deploy the contact email function
supabase functions deploy send-contact-email

# Set the Resend API key as a secret
supabase secrets set RESEND_API_KEY=re_aK7VyMyF_MTdDS2wdfr3vd7mAKZUtzFhr
```

## Step 3: Verify Domain in Resend

1. Go to [resend.com/domains](https://resend.com/domains)
2. Add domain: `schoolair.org`
3. Add the required DNS records to your domain:
   - SPF record
   - DKIM record
   - DMARC record (optional but recommended)

4. Verify the domain
5. Wait for DNS propagation (can take up to 48 hours)

## Step 4: Test the Integration

### Test from Local Development

You can test the function locally before deploying:

```bash
# Start Supabase locally
supabase start

# Serve the edge function locally
supabase functions serve send-contact-email --env-file .env.local

# In another terminal, test with curl:
curl -i --location --request POST \
  'http://localhost:54321/functions/v1/send-contact-email' \
  --header 'Content-Type: application/json' \
  --data '{"name":"Test User","email":"test@example.com","message":"This is a test message","requestType":"general","language":"en"}'
```

### Test from Production Website

1. Open any language version of the site (e.g., `https://schoolair.org/en/`)
2. Scroll to the contact section
3. Fill out the form with test data
4. Submit the form
5. Check browser console for success/error messages
6. Check your email at `info@alellagreentech.com`

### Monitor Edge Function Logs

```bash
# View real-time logs
supabase functions logs send-contact-email --tail
```

## Configuration Details

### Email Recipients

- **To**: `info@alellagreentech.com` (all contact form submissions go here)
- **From**: `info@schoolair.org` (sender address)
- **Reply-To**: User's email address (so you can reply directly)

### Supported Languages

The edge function automatically formats emails based on the language:
- `en` - English
- `es` - Spanish (Español)
- `ca` - Catalan (Català)
- `fr` - French (Français)
- `it` - Italian (Italiano)

### Form Fields

All language versions capture:
- First Name & Last Name
- Email
- School/Organization
- Role (Teacher, Administrator, Student, Researcher, Other)
- Interest Level (Complete Kit, Plans Only, School Partnership, More Information)
- Message

## Troubleshooting

### Domain Not Verified

If emails aren't sending, check domain verification status:

```bash
# Check Resend dashboard
# Visit: https://resend.com/domains
```

**Symptoms**: Edge function returns success but no email is received

**Solution**: Complete domain verification steps, or temporarily test with a verified domain like `info@alellagreentech.com`

### CORS Errors

If you see CORS errors in browser console:

**Symptoms**: `Access-Control-Allow-Origin` error

**Solution**: The edge function already includes CORS headers. Make sure you're deploying the latest version:

```bash
supabase functions deploy send-contact-email --no-verify-jwt
```

### Function Not Found (404)

**Symptoms**: `404 Not Found` when submitting form

**Solution**:
1. Verify function is deployed: `supabase functions list`
2. Check the function URL in HTML files matches your project
3. Redeploy if necessary

### Email Goes to Spam

If emails are landing in spam:

1. Complete SPF, DKIM, DMARC setup in Resend
2. Warm up your domain by sending test emails
3. Ask recipient to whitelist `info@schoolair.org`
4. Check email content doesn't trigger spam filters

### API Key Invalid

**Symptoms**: `Invalid API key` error in logs

**Solution**: Reset the secret:

```bash
supabase secrets set RESEND_API_KEY=re_aK7VyMyF_MTdDS2wdfr3vd7mAKZUtzFhr
```

## Security Notes

- ✅ API key is stored as Supabase secret (not exposed in frontend)
- ✅ CORS is configured to allow requests from your domain
- ✅ Edge function has JWT verification disabled for public access
- ✅ Reply-to field allows direct communication without exposing admin email in form

## Monitoring

### Check Email Delivery

- **Resend Dashboard**: [resend.com/emails](https://resend.com/emails)
  - View sent emails
  - Check delivery status
  - See bounce/complaint rates

### Check Function Performance

```bash
# View function metrics
supabase functions inspect send-contact-email

# View recent logs
supabase functions logs send-contact-email --limit 50
```

## Cost Estimation

### Resend Pricing
- Free tier: 100 emails/day, 3,000 emails/month
- If you exceed, you'll need to upgrade to a paid plan

### Supabase Pricing
- Free tier includes: 500K Edge Function invocations/month
- Current usage: ~1-2 contact form submissions per day = well within free tier

## Updating the Function

If you need to modify the email template or logic:

1. Edit `supabase/functions/send-contact-email/index.ts`
2. Test locally: `supabase functions serve send-contact-email`
3. Deploy changes: `supabase functions deploy send-contact-email`

## Files Modified

- ✅ `supabase/functions/send-contact-email/index.ts` - Edge function
- ✅ `supabase/config.toml` - Supabase configuration
- ✅ `en/index.html` - English contact form
- ✅ `es/index.html` - Spanish contact form
- ✅ `ca/index.html` - Catalan contact form
- ✅ `fr/index.html` - French contact form
- ✅ `it/index.html` - Italian contact form

## Next Steps

1. ✅ Deploy the edge function
2. ✅ Set up domain verification in Resend
3. ✅ Test the contact form
4. 📧 Start receiving contact form submissions at info@alellagreentech.com!

## Support

If you encounter issues:
- Check Supabase logs: `supabase functions logs send-contact-email`
- Check Resend dashboard for email delivery status
- Verify domain is verified in Resend
- Test with curl to isolate frontend vs backend issues
