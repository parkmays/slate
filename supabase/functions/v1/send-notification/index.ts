import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { SmtpClient } from "https://deno.land/x/smtp@v0.7.0/mod.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-internal-secret',
}

interface SendNotificationRequest {
  event: 'share_link_created' | 'annotation_added' | 'review_status_changed' | 'alternate_requested'
  recipientEmail: string
  recipientName?: string
  reviewUrl: string
  projectName?: string
  clipName?: string
  annotationBody?: string
  newStatus?: string
  requesterNote?: string
  senderName?: string
}

const RATE_LIMIT_WINDOW_MS = 60_000
const RATE_LIMIT_MAX_REQUESTS = 30
// NOTE: This in-memory rate limit resets on every cold start and is not shared
// across multiple Edge Function instances. It provides best-effort protection only.
// For production-grade rate limiting, use a shared store such as Upstash Redis
// (via the Supabase Redis integration) keyed on recipient email.
const emailRateLimit = new Map<string, number[]>()

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function errorResponse(status: number, error: string, code: string): Response {
  return jsonResponse({ error, code }, status)
}

function enforceRateLimit(recipientEmail: string): boolean {
  const now = Date.now()

  for (const [key, timestamps] of emailRateLimit.entries()) {
    const fresh = timestamps.filter((timestamp) => now - timestamp < RATE_LIMIT_WINDOW_MS)
    if (fresh.length === 0) {
      emailRateLimit.delete(key)
    } else {
      emailRateLimit.set(key, fresh)
    }
  }

  const attempts = emailRateLimit.get(recipientEmail) ?? []
  const freshAttempts = attempts.filter((timestamp) => now - timestamp < RATE_LIMIT_WINDOW_MS)
  if (freshAttempts.length >= RATE_LIMIT_MAX_REQUESTS) {
    emailRateLimit.set(recipientEmail, freshAttempts)
    return false
  }

  emailRateLimit.set(recipientEmail, [...freshAttempts, now])
  return true
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function buildEmailContent(
  event: SendNotificationRequest['event'],
  body: SendNotificationRequest
): { subject: string; plaintext: string; html: string } {
  switch (event) {
    case 'share_link_created': {
      const projectDisplay = body.projectName ? ` for ${body.projectName}` : ''
      return {
        subject: `You've been invited to review${projectDisplay}`,
        plaintext: `You've been invited to review${projectDisplay}.

Click the link below to access the review:
${body.reviewUrl}

This link will expire in 7 days.`,
        html: `<p>You've been invited to review${escapeHtml(projectDisplay)}.</p>
<p><a href="${escapeHtml(body.reviewUrl)}">Access the review</a></p>
<p>This link will expire in 7 days.</p>`,
      }
    }

    case 'annotation_added': {
      const clipDisplay = body.clipName ? ` on ${body.clipName}` : ''
      const senderDisplay = body.senderName ? ` by ${body.senderName}` : ''
      return {
        subject: `New annotation${clipDisplay}${senderDisplay}`,
        plaintext: `A new annotation has been added${clipDisplay}${senderDisplay}.

${body.annotationBody || ''}

Review it here:
${body.reviewUrl}`,
        html: `<p>A new annotation has been added${escapeHtml(clipDisplay)}${escapeHtml(senderDisplay)}.</p>
<p><strong>${escapeHtml(body.annotationBody || '')}</strong></p>
<p><a href="${escapeHtml(body.reviewUrl)}">View the review</a></p>`,
      }
    }

    case 'review_status_changed': {
      const clipDisplay = body.clipName ? ` ${body.clipName}` : ''
      const statusDisplay = body.newStatus ? ` to ${body.newStatus}` : ''
      return {
        subject: `Status updated${statusDisplay}`,
        plaintext: `The status of${clipDisplay} has been updated${statusDisplay}.

Review the change here:
${body.reviewUrl}`,
        html: `<p>The status of${escapeHtml(clipDisplay)} has been updated${escapeHtml(statusDisplay)}.</p>
<p><a href="${escapeHtml(body.reviewUrl)}">View the review</a></p>`,
      }
    }

    case 'alternate_requested': {
      const clipDisplay = body.clipName ? ` for ${body.clipName}` : ''
      return {
        subject: `Alternate take requested${clipDisplay}`,
        plaintext: `An alternate take has been requested${clipDisplay}.

${body.requesterNote ? `Note: ${body.requesterNote}` : ''}

Review the request here:
${body.reviewUrl}`,
        html: `<p>An alternate take has been requested${escapeHtml(clipDisplay)}.</p>
${body.requesterNote ? `<p>${escapeHtml(body.requesterNote)}</p>` : ''}
<p><a href="${escapeHtml(body.reviewUrl)}">View the review</a></p>`,
      }
    }

    default:
      throw new Error(`Unknown event type: ${event}`)
  }
}

async function sendViaSmtp(
  fromEmail: string,
  toEmail: string,
  subject: string,
  plaintext: string,
  html: string
): Promise<void> {
  const smtpHost = Deno.env.get('SMTP_HOST')
  const smtpPort = parseInt(Deno.env.get('SMTP_PORT') || '587', 10)
  const smtpUser = Deno.env.get('SMTP_USER')
  const smtpPass = Deno.env.get('SMTP_PASS')

  if (!smtpHost || !smtpUser || !smtpPass) {
    throw new Error('SMTP not configured')
  }

  const client = new SmtpClient({
    hostname: smtpHost,
    port: smtpPort,
    username: smtpUser,
    password: smtpPass,
  })

  await client.connect()
  try {
    await client.send({
      from: fromEmail,
      to: toEmail,
      subject,
      content: plaintext,
      html,
    })
  } finally {
    await client.close()
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Authentication check
    const authHeader = req.headers.get('Authorization')
    const internalSecret = req.headers.get('X-Internal-Secret')
    const slateInternalSecret = Deno.env.get('SLATE_INTERNAL_SECRET')

    const isAuthorized =
      (authHeader && authHeader.startsWith('Bearer ')) ||
      (internalSecret && slateInternalSecret && internalSecret === slateInternalSecret)

    if (!isAuthorized) {
      return errorResponse(401, 'Missing or invalid authorization', 'missing_authorization')
    }

    // If using Bearer token, validate it with Supabase
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const supabaseUrl = Deno.env.get('SUPABASE_URL')
      const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
      if (!supabaseUrl || !supabaseServiceKey) {
        return errorResponse(500, 'Supabase environment is not configured', 'supabase_env_missing')
      }

      const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2')
      const supabase = createClient(supabaseUrl, supabaseServiceKey)
      const token = authHeader.replace('Bearer ', '')
      const { data: authData, error: authError } = await supabase.auth.getUser(token)
      if (authError || !authData.user) {
        return errorResponse(401, 'Invalid authentication token', 'invalid_authentication')
      }
    }

    const body: SendNotificationRequest = await req.json()
    const { event, recipientEmail, recipientName, reviewUrl, projectName, clipName, annotationBody, newStatus, requesterNote, senderName } = body

    // Validate required fields
    if (!event || !recipientEmail || !reviewUrl) {
      return errorResponse(400, 'Missing required fields: event, recipientEmail, reviewUrl', 'missing_fields')
    }

    // Validate event type
    const validEvents = new Set(['share_link_created', 'annotation_added', 'review_status_changed', 'alternate_requested'])
    if (!validEvents.has(event)) {
      return errorResponse(400, 'Invalid event type', 'invalid_event_type')
    }

    // Rate limiting
    if (!enforceRateLimit(recipientEmail)) {
      return errorResponse(429, 'Rate limit exceeded for this recipient', 'rate_limited')
    }

    // Build email content
    const { subject, plaintext, html } = buildEmailContent(event, {
      event,
      recipientEmail,
      recipientName,
      reviewUrl,
      projectName,
      clipName,
      annotationBody,
      newStatus,
      requesterNote,
      senderName,
    })

    const fromEmail = Deno.env.get('SLATE_FROM_EMAIL') || 'SLATE Dailies <noreply@slate.app>'
    const smtpHost = Deno.env.get('SMTP_HOST')

    // If SMTP is not configured, return gracefully
    if (!smtpHost) {
      console.warn('SMTP not configured, skipping email send')
      return jsonResponse({ sent: false, reason: 'SMTP not configured' })
    }

    // Try to send via SMTP
    try {
      await sendViaSmtp(fromEmail, recipientEmail, subject, plaintext, html)
      return jsonResponse({ sent: true })
    } catch (smtpError) {
      console.error('SMTP error:', smtpError)
      return errorResponse(500, 'Failed to send email', 'email_send_failed')
    }
  } catch (error) {
    console.error('Error in send-notification:', error)
    return errorResponse(500, 'Internal server error', 'internal_error')
  }
})
