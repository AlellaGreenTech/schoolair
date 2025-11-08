// Supabase Edge Function to send contact form emails via Resend
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || 're_aK7VyMyF_MTdDS2wdfr3vd7mAKZUtzFhr'
const FROM_EMAIL = 'info@schoolair.org'
const TO_EMAIL = 'info@alellagreentech.com'

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      }
    })
  }

  try {
    const { name, email, message, requestType, language } = await req.json()

    if (!name || !email || !message) {
      throw new Error('Missing required fields: name, email, or message')
    }

    // Language-specific subjects
    const subjects: Record<string, string> = {
      'en': 'New SchoolAIR Contact Form Submission',
      'es': 'Nueva Solicitud de Contacto - SchoolAIR',
      'ca': 'Nova Sol·licitud de Contacte - SchoolAIR',
      'fr': 'Nouvelle Demande de Contact - SchoolAIR',
      'it': 'Nuova Richiesta di Contatto - SchoolAIR'
    }

    const requestTypeLabels: Record<string, Record<string, string>> = {
      'en': {
        'school_inquiry': 'School Inquiry',
        'partnership': 'Partnership Opportunity',
        'technical_support': 'Technical Support',
        'general': 'General Information'
      },
      'es': {
        'school_inquiry': 'Consulta Escolar',
        'partnership': 'Oportunidad de Asociación',
        'technical_support': 'Soporte Técnico',
        'general': 'Información General'
      },
      'ca': {
        'school_inquiry': 'Consulta Escolar',
        'partnership': 'Oportunitat d\'Associació',
        'technical_support': 'Suport Tècnic',
        'general': 'Informació General'
      },
      'fr': {
        'school_inquiry': 'Demande Scolaire',
        'partnership': 'Opportunité de Partenariat',
        'technical_support': 'Support Technique',
        'general': 'Information Générale'
      },
      'it': {
        'school_inquiry': 'Richiesta Scolastica',
        'partnership': 'Opportunità di Partnership',
        'technical_support': 'Supporto Tecnico',
        'general': 'Informazioni Generali'
      }
    }

    const currentLang = language || 'en'
    const emailSubject = subjects[currentLang] || subjects['en']
    const requestTypeLabel = requestType
      ? (requestTypeLabels[currentLang]?.[requestType] || requestType)
      : 'Not specified'

    // Build email HTML
    const emailBody = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
      </head>
      <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #4CAF50 0%, #2e7d32 100%); padding: 30px; text-align: center; border-radius: 10px 10px 0 0;">
          <h1 style="color: white; margin: 0; font-size: 28px;">SchoolAIR Contact Form</h1>
          <p style="color: white; margin-top: 10px; opacity: 0.9;">New Message Received</p>
        </div>

        <div style="background: white; padding: 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 10px 10px;">
          <div style="background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 25px 0;">
            <h2 style="color: #4CAF50; margin-top: 0;">Contact Details</h2>

            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 8px 0; font-weight: bold; width: 40%;">Name:</td>
                <td style="padding: 8px 0;">${name}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold;">Email:</td>
                <td style="padding: 8px 0;"><a href="mailto:${email}" style="color: #4CAF50;">${email}</a></td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold;">Request Type:</td>
                <td style="padding: 8px 0;">${requestTypeLabel}</td>
              </tr>
              <tr>
                <td style="padding: 8px 0; font-weight: bold;">Language:</td>
                <td style="padding: 8px 0;">${currentLang.toUpperCase()}</td>
              </tr>
            </table>
          </div>

          <div style="background: #e8f5e9; padding: 20px; border-radius: 8px; margin: 25px 0; border-left: 4px solid #4CAF50;">
            <h3 style="color: #2e7d32; margin-top: 0;">Message</h3>
            <p style="white-space: pre-wrap; margin: 0;">${message}</p>
          </div>

          <hr style="border: none; border-top: 1px solid #e0e0e0; margin: 30px 0;">

          <p style="font-size: 12px; color: #999; text-align: center;">
            This email was sent from the SchoolAIR project contact form<br>
            Submitted: ${new Date().toISOString()}<br>
            <a href="https://schoolair.org" style="color: #4CAF50;">schoolair.org</a>
          </p>
        </div>
      </body>
      </html>
    `

    console.log('Sending contact form email to:', TO_EMAIL)
    console.log('From:', email)
    console.log('Name:', name)

    // Send email via Resend
    const emailPayload = {
      from: FROM_EMAIL,
      to: [TO_EMAIL],
      reply_to: email,
      subject: `${emailSubject} - ${name}`,
      html: emailBody
    }

    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`
      },
      body: JSON.stringify(emailPayload)
    })

    const resendData = await resendResponse.json()

    if (!resendResponse.ok) {
      console.error('Resend API error:', resendData)
      throw new Error(`Resend API error: ${JSON.stringify(resendData)}`)
    }

    console.log('Email sent successfully:', resendData.id)

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Contact form email sent successfully',
        resendId: resendData.id
      }),
      {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    )

  } catch (error) {
    console.error('Error sending contact email:', error)

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message
      }),
      {
        status: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    )
  }
})
