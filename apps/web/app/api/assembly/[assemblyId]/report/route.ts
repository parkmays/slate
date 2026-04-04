import { NextRequest, NextResponse } from 'next/server'
import { createServerSupabaseClient } from '@/lib/supabase'
import { ReviewRouteError, loadAssemblyData, requireShareLinkAccess } from '@/lib/review-server'

type ReportFormat = 'csv' | 'html'
type ClipAnnotationStats = Record<string, { count: number; hasAlternateRequest: boolean }>

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

async function loadClipMetadata(
  supabase: any,
  clipIds: string[]
): Promise<Record<string, any>> {
  if (clipIds.length === 0) {
    return {}
  }

  const { data, error } = await supabase
    .from('clips')
    .select('id, hierarchy, ai_scores, review_status, metadata')
    .in('id', clipIds)

  if (error || !data) {
    return {}
  }

  return data.reduce((acc: Record<string, any>, clip: any) => {
    acc[clip.id] = clip
    return acc
  }, {})
}

async function loadClipAnnotations(
  supabase: any,
  clipIds: string[]
): Promise<ClipAnnotationStats> {
  if (clipIds.length === 0) {
    return {}
  }

  const { data, error } = await supabase
    .from('annotations')
    .select('clip_id, content')
    .in('clip_id', clipIds)

  if (error || !data) {
    return {}
  }

  return data.reduce((acc: ClipAnnotationStats, annotation: any) => {
    const clipId = annotation.clip_id
    const content = typeof annotation.content === 'string' ? annotation.content.toUpperCase() : ''
    const previous = acc[clipId] ?? { count: 0, hasAlternateRequest: false }

    acc[clipId] = {
      count: previous.count + 1,
      hasAlternateRequest: previous.hasAlternateRequest || content.startsWith('REQUEST ALTERNATE:'),
    }

    return acc
  }, {})
}

function formatCSV(value: string | number | boolean | null | undefined): string {
  if (value === null || value === undefined) {
    return ''
  }

  const str = String(value)
  const safeValue = /^[=+\-@]/.test(str) ? `'${str}` : str
  if (safeValue.includes(',') || safeValue.includes('"') || safeValue.includes('\n')) {
    return `"${safeValue.replace(/"/g, '""')}"`
  }
  return safeValue
}

function getClipMetadata(clip: any, hierarchy: any) {
  const narrative = hierarchy?.narrative
  const documentary = hierarchy?.documentary

  return {
    sceneNumber: narrative?.sceneNumber ?? 'N/A',
    take: narrative?.takeNumber ?? 'N/A',
    camera: clip?.metadata?.camera?.model ?? narrative?.cameraId ?? 'Unknown',
    subjectName: documentary?.subjectName ?? 'N/A',
  }
}

function generateCSV(
  assemblyData: any,
  clipMetadata: Record<string, any>,
  annotationStats: ClipAnnotationStats
): string {
  const headers = ['Clip ID', 'Scene', 'Take', 'Camera', 'Duration (s)', 'AI Composite', 'Status', 'Annotation Count', 'Requested Alternate']
  const rows: string[][] = [headers]

  for (const clip of assemblyData.clips) {
    const metadata = clipMetadata[clip.clipId]
    const hierarchy = metadata?.hierarchy ?? {}
    const clipInfo = getClipMetadata(metadata, hierarchy)
    const aiScores = metadata?.ai_scores
    const reviewStatus = metadata?.review_status ?? 'unreviewed'
    const stats = annotationStats[clip.clipId] ?? { count: 0, hasAlternateRequest: false }
    const annotationCount = stats.count
    const hasAlternateRequest = stats.hasAlternateRequest

    rows.push([
      formatCSV(clip.clipId),
      formatCSV(clipInfo.sceneNumber),
      formatCSV(clipInfo.take),
      formatCSV(clipInfo.camera),
      formatCSV(clip.duration ?? ''),
      formatCSV(aiScores?.composite ?? ''),
      formatCSV(reviewStatus),
      formatCSV(annotationCount),
      formatCSV(hasAlternateRequest ? 'Yes' : 'No'),
    ])
  }

  return rows.map((row) => row.join(',')).join('\n')
}

function generateHTML(
  assemblyData: any,
  clipMetadata: Record<string, any>,
  annotationStats: ClipAnnotationStats
): string {
  const now = new Date().toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })

  const tableRows = assemblyData.clips
    .map((clip: any) => {
      const metadata = clipMetadata[clip.clipId]
      const hierarchy = metadata?.hierarchy ?? {}
      const clipInfo = getClipMetadata(metadata, hierarchy)
      const aiScores = metadata?.ai_scores
      const reviewStatus = metadata?.review_status ?? 'unreviewed'
      const stats = annotationStats[clip.clipId] ?? { count: 0, hasAlternateRequest: false }
      const annotationCount = stats.count
      const hasAlternateRequest = stats.hasAlternateRequest

      return `
      <tr>
        <td>${escapeHtml(String(clip.clipId))}</td>
        <td>${escapeHtml(String(clipInfo.sceneNumber))}</td>
        <td>${escapeHtml(String(clipInfo.take))}</td>
        <td>${escapeHtml(String(clipInfo.camera))}</td>
        <td>${escapeHtml(String(clip.duration ?? ''))}</td>
        <td>${escapeHtml(String(aiScores?.composite ?? ''))}</td>
        <td>${escapeHtml(String(reviewStatus))}</td>
        <td>${annotationCount}</td>
        <td>${hasAlternateRequest ? 'Yes' : 'No'}</td>
      </tr>
      `
    })
    .join('')

  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SLATE Dailies Report — ${escapeHtml(String(assemblyData.title))} — ${escapeHtml(now)}</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      line-height: 1.6;
      color: #1f2937;
      background: #f9fafb;
      margin: 0;
      padding: 20px;
    }
    .container {
      max-width: 1200px;
      margin: 0 auto;
      background: white;
      padding: 40px;
      border-radius: 8px;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
    }
    h1 {
      margin: 0 0 10px 0;
      font-size: 28px;
      font-weight: 600;
    }
    .header-info {
      margin-bottom: 30px;
      padding-bottom: 20px;
      border-bottom: 1px solid #e5e7eb;
      font-size: 14px;
      color: #6b7280;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 20px;
    }
    th {
      background: #f3f4f6;
      padding: 12px;
      text-align: left;
      font-weight: 600;
      font-size: 13px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      border: 1px solid #e5e7eb;
    }
    td {
      padding: 12px;
      border: 1px solid #e5e7eb;
      font-size: 14px;
    }
    tr:nth-child(even) {
      background: #f9fafb;
    }
    @media print {
      body {
        background: white;
        padding: 0;
      }
      .container {
        box-shadow: none;
        padding: 0;
        max-width: 100%;
      }
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>SLATE Dailies Report</h1>
    <div class="header-info">
      <p><strong>Assembly:</strong> ${escapeHtml(String(assemblyData.title))}</p>
      <p><strong>Version:</strong> ${escapeHtml(String(assemblyData.versionLabel))}</p>
      <p><strong>Generated:</strong> ${escapeHtml(now)}</p>
    </div>
    <table>
      <thead>
        <tr>
          <th>Clip ID</th>
          <th>Scene</th>
          <th>Take</th>
          <th>Camera</th>
          <th>Duration (s)</th>
          <th>AI Composite</th>
          <th>Status</th>
          <th>Annotation Count</th>
          <th>Requested Alternate</th>
        </tr>
      </thead>
      <tbody>
        ${tableRows}
      </tbody>
    </table>
  </div>
</body>
</html>`
}

export async function GET(
  request: NextRequest,
  { params }: { params: { assemblyId: string } }
) {
  try {
    const shareToken = request.headers.get('X-Share-Token') ?? request.nextUrl.searchParams.get('token')
    const format = (request.nextUrl.searchParams.get('format') ?? 'csv') as ReportFormat

    if (!params.assemblyId) {
      return NextResponse.json({ error: 'Missing assemblyId' }, { status: 400 })
    }

    if (!shareToken) {
      return NextResponse.json({ error: 'Missing share token' }, { status: 401 })
    }

    if (!['csv', 'html'].includes(format)) {
      return NextResponse.json({ error: 'Invalid format' }, { status: 400 })
    }

    const supabase = createServerSupabaseClient()
    const shareLink = await requireShareLinkAccess(supabase, shareToken, request)

    if (shareLink.scope !== 'assembly' || shareLink.scope_id !== params.assemblyId) {
      return NextResponse.json({ error: 'Assembly access is not permitted for this share link' }, { status: 403 })
    }

    const assembly = await loadAssemblyData(supabase, params.assemblyId)
    const clipIds = assembly.clips.map((clip) => clip.clipId)

    const [clipMetadata, annotationStats] = await Promise.all([
      loadClipMetadata(supabase, clipIds),
      loadClipAnnotations(supabase, clipIds),
    ])

    if (format === 'csv') {
      const csv = generateCSV(assembly, clipMetadata, annotationStats)
      const now = new Date().toISOString().split('T')[0]
      return new NextResponse(csv, {
        headers: {
          'Content-Type': 'text/csv',
          'Content-Disposition': `attachment; filename="slate-dailies-${now}.csv"`,
        },
      })
    }

    // HTML format
    const html = generateHTML(assembly, clipMetadata, annotationStats)
    return new NextResponse(html, {
      headers: {
        'Content-Type': 'text/html',
      },
    })
  } catch (error) {
    if (error instanceof ReviewRouteError) {
      return NextResponse.json({ error: error.message }, { status: error.status })
    }

    console.error('Assembly report error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
