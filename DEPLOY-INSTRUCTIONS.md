# Quick Deployment Guide

## Deploy the Supabase Edge Function

Run these commands from the schoolair project directory:

```bash
# 1. Login to Supabase (if not already logged in)
supabase login

# 2. Link to your project
supabase link --project-ref gzbuvywxrzcovqohmbol

# 3. Deploy the edge function
supabase functions deploy send-contact-email

# 4. Set the Resend API key as a secret
supabase secrets set RESEND_API_KEY=re_aK7VyMyF_MTdDS2wdfr3vd7mAKZUtzFhr
```

## Verify Domain in Resend

**IMPORTANT**: Before emails will send from `info@schoolair.org`, you must verify the domain in Resend:

1. Go to https://resend.com/domains
2. Add `schoolair.org` as a domain
3. Add the DNS records provided by Resend to your domain DNS settings
4. Wait for verification (can take up to 48 hours)

## Test the Integration

After deployment:

1. Visit https://schoolair.org/en/
2. Fill out the contact form
3. Submit and check for success message
4. Verify email received at info@alellagreentech.com

## Monitor Logs

```bash
# View real-time logs
supabase functions logs send-contact-email --tail
```

## That's it!

Your contact forms will now send emails via Resend instead of opening mailto links.

For detailed troubleshooting, see [SETUP-EMAIL.md](./SETUP-EMAIL.md)
