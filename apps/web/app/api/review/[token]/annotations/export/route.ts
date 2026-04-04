import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import {
  ReviewRouteError,
  filterClipRowsForShareLink,
  normalizeAnnotation,
  requireShareLinkAccess,
} from '@/lib/review-server'

type ExportFormat = 'csv' | 'json' | 'html'

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function csvEscape(value: string | number | boolean | null): string {
  if (value == null) {
    return ''
  }

  const str = String(value)
  const safeValue = /^[=+\-@]/.test(str) ? `'${str}` : str
  return /[",\n]/.test(safeValue) ? `"${safeValue.replace(/"/g, '""')}"` : safeValue
}

export async function GET(
  request: NextRequest,
  { params }: { params: { token: string } }
) {
  try {
    const format = (request.nextUrl.searchParams.get('format') ?? 'csv') as ExportFormat
    const shareToken = params.token

    if (!['csv', 'json', 'html'].includes(format)) {
      return NextResponse.json({ error: 'Unsupported export format' }, { status: 400 })
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)

    const { data: clipRows } = await supabase
      .from('clips')
      .select('id, hierarchy, review_status')
      .eq('project_id', shareLink.project_id)

    const visibleClipRows = await filterClipRowsForShareLink(supabase, shareLink, clipRows ?? [])
    const clipIds = visibleClipRows.map((clip) => clip.id)
    const { data: annotationRows } = clipIds.length === 0
      ? { data: [] as any[] }
      : await supabase
          .from('annotations')
          .select('*')
          .in('clip_id', clipIds)
          .order('created_at', { ascending: true })

    const normalized = (annotationRows ?? []).map((row) => ({
      clipId: row.clip_id,
      ...normalizeAnnotation(row),
    }))

    if (format === 'json') {
      return NextResponse.json({
        exportedAt: new Date().toISOString(),
        shareLink: {
          token: shareToken,
          scope: shareLink.scope,
        },
        annotations: normalized,
      })
    }

    if (format === 'html') {
      const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>SLATE Annotation Export</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 40px; color: #18181b; }
    h1 { margin-bottom: 0.25rem; }
    p { color: #52525b; }
    table { width: 100%; border-collapse: collapse; margin-top: 24px; }
    th, td { border: 1px solid #e4e4e7; padding: 10px; text-align: left; vertical-align: top; }
    th { background: #f4f4f5; font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; }
    audio { width: 220px; }
  </style>
</head>
<body>
  <h1>SLATE Annotation Export</h1>
  <p>Generated ${escapeHtml(new Date().toLocaleString())} for ${escapeHtml(shareLink.scope)} review link.</p>
  <table>
    <thead>
      <tr>
        <th>Clip</th>
        <th>Timecode</th>
        <th>Type</th>
        <th>Author</th>
        <th>Resolved</th>
        <th>Body</th>
      </tr>
    </thead>
    <tbody>
      ${normalized.map((annotation) => `
        <tr>
          <td>${escapeHtml(annotation.clipId)}</td>
          <td>${escapeHtml(annotation.timecodeIn)}</td>
          <td>${escapeHtml(annotation.type)}</td>
          <td>${escapeHtml(annotation.userDisplayName)}</td>
          <td>${annotation.isResolved ? 'Yes' : 'No'}</td>
          <td>${annotation.voiceUrl ? `<audio controls src="${escapeHtml(annotation.voiceUrl)}"></audio>` : escapeHtml(annotation.body)}</td>
        </tr>
      `).join('')}
    </tbody>
  </table>
</body>
</html>`

      return new NextResponse(html, {
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
        },
      })
    }

    const rows = [
      ['clipId', 'timecodeIn', 'type', 'author', 'resolved', 'mentions', 'body'],
      ...normalized.map((annotation) => ([
        csvEscape(annotation.clipId),
        csvEscape(annotation.timecodeIn),
        csvEscape(annotation.type),
        csvEscape(annotation.userDisplayName),
        csvEscape(annotation.isResolved),
        csvEscape(annotation.mentions.join(' ')),
        csvEscape(annotation.voiceUrl ?? annotation.body),
      ])),
    ]

    return new NextResponse(rows.map((row) => row.join(',')).join('\n'), {
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': 'attachment; filename="slate-annotations.csv"',
      },
    })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Annotation export error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
