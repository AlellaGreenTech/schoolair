const RESEND_API_URL = 'https://api.resend.com/emails'
const FROM_EMAIL = 'SchoolAIR <info@schoolair.org>'

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
