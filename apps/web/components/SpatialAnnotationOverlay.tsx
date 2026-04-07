'use client'

import React, { useEffect, useMemo, useRef, useState } from 'react'
import type { ReviewAnnotation, SpatialAnnotationPayload, SpatialPoint, SpatialShape } from '@/lib/review-types'

type DrawingTool = 'freehand' | 'arrow' | 'ellipse'

interface OverlayRect {
  left: number
  top: number
  width: number
  height: number
}

interface SpatialAnnotationOverlayProps {
  videoRef: React.RefObject<HTMLVideoElement>
  annotations: ReviewAnnotation[]
  onSave: (payload: SpatialAnnotationPayload) => void
  disabled?: boolean
}

function clamp01(value: number): number {
  if (value < 0) return 0
  if (value > 1) return 1
  return value
}

function viewPointFromEvent(event: React.PointerEvent<SVGSVGElement>, rect: OverlayRect): SpatialPoint {
  return {
    x: clamp01((event.clientX - rect.left) / Math.max(rect.width, 1)),
    y: clamp01((event.clientY - rect.top) / Math.max(rect.height, 1)),
  }
}

function useVideoContentRect(videoRef: React.RefObject<HTMLVideoElement>): OverlayRect | null {
  const [rect, setRect] = useState<OverlayRect | null>(null)

  useEffect(() => {
    const video = videoRef.current
    if (!video) {
      return
    }

    const compute = () => {
      const width = video.clientWidth
      const height = video.clientHeight
      if (width <= 0 || height <= 0) {
        return
      }
      const sourceWidth = video.videoWidth || 16
      const sourceHeight = video.videoHeight || 9
      const sourceRatio = sourceWidth / sourceHeight
      const boxRatio = width / height

      if (sourceRatio > boxRatio) {
        const fittedHeight = width / sourceRatio
        setRect({
          left: 0,
          top: (height - fittedHeight) / 2,
          width,
          height: fittedHeight,
        })
      } else {
        const fittedWidth = height * sourceRatio
        setRect({
          left: (width - fittedWidth) / 2,
          top: 0,
          width: fittedWidth,
          height,
        })
      }
    }

    const observer = new ResizeObserver(() => compute())
    observer.observe(video)
    const onLoaded = () => compute()
    video.addEventListener('loadedmetadata', onLoaded)
    compute()

    return () => {
      observer.disconnect()
      video.removeEventListener('loadedmetadata', onLoaded)
    }
  }, [videoRef])

  return rect
}

function renderShape(shape: SpatialShape, key: string) {
  if (shape.kind === 'arrow') {
    const dx = shape.to.x - shape.from.x
    const dy = shape.to.y - shape.from.y
    const len = Math.sqrt(dx * dx + dy * dy) || 1
    const ux = dx / len
    const uy = dy / len
    const headSize = Math.max(0.02, shape.strokeWidthNorm * 3)
    const leftX = shape.to.x - ux * headSize - uy * headSize * 0.6
    const leftY = shape.to.y - uy * headSize + ux * headSize * 0.6
    const rightX = shape.to.x - ux * headSize + uy * headSize * 0.6
    const rightY = shape.to.y - uy * headSize - ux * headSize * 0.6

    return (
      <g key={key}>
        <line
          x1={shape.from.x}
          y1={shape.from.y}
          x2={shape.to.x}
          y2={shape.to.y}
          stroke={shape.stroke}
          strokeWidth={shape.strokeWidthNorm}
          vectorEffect="non-scaling-stroke"
          strokeLinecap="round"
        />
        <polygon
          points={`${shape.to.x},${shape.to.y} ${leftX},${leftY} ${rightX},${rightY}`}
          fill={shape.stroke}
        />
      </g>
    )
  }

  if (shape.kind === 'ellipse') {
    return (
      <ellipse
        key={key}
        cx={shape.cx}
        cy={shape.cy}
        rx={shape.rx}
        ry={shape.ry}
        stroke={shape.stroke}
        strokeWidth={shape.strokeWidthNorm}
        vectorEffect="non-scaling-stroke"
        fill="transparent"
      />
    )
  }

  const points = shape.points.map((p) => `${p.x},${p.y}`).join(' ')
  return (
    <polyline
      key={key}
      points={points}
      stroke={shape.stroke}
      strokeWidth={shape.strokeWidthNorm}
      vectorEffect="non-scaling-stroke"
      strokeLinecap="round"
      strokeLinejoin="round"
      fill="none"
    />
  )
}

export function SpatialAnnotationOverlay({
  videoRef,
  annotations,
  onSave,
  disabled = false,
}: SpatialAnnotationOverlayProps) {
  const overlayRect = useVideoContentRect(videoRef)
  const [tool, setTool] = useState<DrawingTool>('freehand')
  const [stroke, setStroke] = useState('#f97316')
  const [strokeWidthNorm, setStrokeWidthNorm] = useState(0.004)
  const [draftShapes, setDraftShapes] = useState<SpatialShape[]>([])
  const drawingRef = useRef<SpatialShape | null>(null)
  const [activeShape, setActiveShape] = useState<SpatialShape | null>(null)
  const isDrawingEnabled = !disabled

  const savedShapes = useMemo(() => {
    return annotations
      .flatMap((annotation) => annotation.spatialData?.shapes ?? [])
  }, [annotations])

  function beginShape(event: React.PointerEvent<SVGSVGElement>) {
    if (!overlayRect || !isDrawingEnabled) {
      return
    }
    const start = viewPointFromEvent(event, overlayRect)
    const id = crypto.randomUUID()
    let shape: SpatialShape
    if (tool === 'arrow') {
      shape = { id, kind: 'arrow', from: start, to: start, stroke, strokeWidthNorm }
    } else if (tool === 'ellipse') {
      shape = { id, kind: 'ellipse', cx: start.x, cy: start.y, rx: 0, ry: 0, stroke, strokeWidthNorm }
    } else {
      shape = { id, kind: 'freehand', points: [start], stroke, strokeWidthNorm }
    }
    drawingRef.current = shape
    setActiveShape(shape)
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  function updateShape(event: React.PointerEvent<SVGSVGElement>) {
    if (!overlayRect || !drawingRef.current || !isDrawingEnabled) {
      return
    }
    const next = viewPointFromEvent(event, overlayRect)
    const current = drawingRef.current
    if (current.kind === 'arrow') {
      current.to = next
    } else if (current.kind === 'ellipse') {
      current.rx = Math.abs(next.x - current.cx)
      current.ry = Math.abs(next.y - current.cy)
    } else {
      current.points = [...current.points, next]
    }
    drawingRef.current = { ...current }
    setActiveShape({ ...current })
  }

  function endShape() {
    if (!drawingRef.current || !isDrawingEnabled) {
      return
    }
    const shape = drawingRef.current
    drawingRef.current = null
    setActiveShape(null)
    if (shape.kind === 'freehand' && shape.points.length < 2) {
      return
    }
    if (shape.kind === 'ellipse' && (shape.rx <= 0.001 || shape.ry <= 0.001)) {
      return
    }
    setDraftShapes((previous) => [...previous, shape])
  }

  if (!overlayRect) {
    return null
  }

  return (
    <>
      <div
        className="pointer-events-none absolute"
        style={{
          left: `${overlayRect.left}px`,
          top: `${overlayRect.top}px`,
          width: `${overlayRect.width}px`,
          height: `${overlayRect.height}px`,
        }}
      >
        <svg
          className={isDrawingEnabled ? 'pointer-events-auto h-full w-full' : 'h-full w-full'}
          viewBox="0 0 1 1"
          preserveAspectRatio="none"
          onPointerDown={beginShape}
          onPointerMove={updateShape}
          onPointerUp={endShape}
          onPointerLeave={endShape}
        >
          {savedShapes.map((shape, index) => renderShape(shape, `saved-${index}`))}
          {draftShapes.map((shape, index) => renderShape(shape, `draft-${index}`))}
          {activeShape ? renderShape(activeShape, 'active') : null}
        </svg>
      </div>

      <div className="absolute left-3 top-3 flex items-center gap-2 rounded-lg bg-black/70 px-2 py-1 text-xs text-white">
        <select
          value={tool}
          onChange={(event) => setTool(event.target.value as DrawingTool)}
          className="rounded bg-zinc-900 px-1 py-0.5"
          disabled={!isDrawingEnabled}
        >
          <option value="freehand">Freehand</option>
          <option value="arrow">Arrow</option>
          <option value="ellipse">Ellipse</option>
        </select>
        <input
          type="color"
          value={stroke}
          onChange={(event) => setStroke(event.target.value)}
          disabled={!isDrawingEnabled}
          className="h-6 w-8 rounded border-none bg-transparent p-0"
        />
        <input
          type="range"
          min={0.001}
          max={0.012}
          step={0.001}
          value={strokeWidthNorm}
          onChange={(event) => setStrokeWidthNorm(Number(event.target.value))}
          disabled={!isDrawingEnabled}
        />
        <button
          type="button"
          className="rounded border border-zinc-700 px-2 py-0.5 disabled:opacity-50"
          disabled={draftShapes.length === 0 || !isDrawingEnabled}
          onClick={() => {
            if (draftShapes.length === 0) {
              return
            }
            onSave({
              version: 1,
              shapes: draftShapes,
            })
            setDraftShapes([])
          }}
        >
          Save markup
        </button>
        <button
          type="button"
          className="rounded border border-zinc-700 px-2 py-0.5 disabled:opacity-50"
          disabled={draftShapes.length === 0}
          onClick={() => setDraftShapes((previous) => previous.slice(0, -1))}
        >
          Undo
        </button>
      </div>
    </>
  )
}
