'use client'

import React, { useEffect, useState } from 'react'

interface FaceCluster {
  id: string
  cluster_key: string
  display_name: string | null
  character_name: string | null
  representative_thumbnail_url: string | null
}

interface CastCharactersPanelProps {
  token: string
  clipId: string
}

export function CastCharactersPanel({ token, clipId }: CastCharactersPanelProps) {
  const [clusters, setClusters] = useState<FaceCluster[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    async function load() {
      setLoading(true)
      setError(null)
      try {
        const response = await fetch(`/api/face-clusters/${clipId}`, {
          headers: {
            'X-Share-Token': token,
          },
        })
        const payload = await response.json()
        if (!response.ok) {
          throw new Error(payload.error ?? 'Failed to load cast clusters')
        }
        if (active) {
          setClusters(payload.clusters ?? [])
        }
      } catch (loadError) {
        if (active) {
          setError(loadError instanceof Error ? loadError.message : 'Failed to load cast clusters')
        }
      } finally {
        if (active) {
          setLoading(false)
        }
      }
    }
    void load()
    return () => {
      active = false
    }
  }, [clipId, token])

  async function saveName(cluster: FaceCluster, displayName: string, characterName: string) {
    const response = await fetch(`/api/face-clusters/${clipId}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Share-Token': token,
      },
      body: JSON.stringify({
        shareToken: token,
        clusterKey: cluster.cluster_key,
        displayName,
        characterName,
      }),
    })
    const payload = await response.json()
    if (!response.ok || !payload.cluster) {
      throw new Error(payload.error ?? 'Failed to save cast label')
    }
    setClusters((previous) => previous.map((item) => (
      item.id === cluster.id || item.cluster_key === cluster.cluster_key
        ? payload.cluster as FaceCluster
        : item
    )))
  }

  if (loading) {
    return <div className="rounded-xl border border-zinc-800 bg-zinc-950/70 p-4 text-sm text-zinc-500">Loading cast clusters…</div>
  }

  if (error) {
    return <div className="rounded-xl border border-rose-500/40 bg-rose-500/10 p-4 text-sm text-rose-200">{error}</div>
  }

  if (clusters.length === 0) {
    return (
      <div className="rounded-xl border border-dashed border-zinc-800 bg-zinc-950/40 p-4 text-sm text-zinc-500">
        No face clusters yet. Run AI analysis to detect cast candidates.
      </div>
    )
  }

  return (
    <div className="space-y-3">
      {clusters.map((cluster) => (
        <CastClusterRow key={cluster.id} cluster={cluster} onSave={saveName} />
      ))}
    </div>
  )
}

function CastClusterRow({
  cluster,
  onSave,
}: {
  cluster: FaceCluster
  onSave: (cluster: FaceCluster, displayName: string, characterName: string) => Promise<void>
}) {
  const [displayName, setDisplayName] = useState(cluster.display_name ?? '')
  const [characterName, setCharacterName] = useState(cluster.character_name ?? '')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-950/70 p-3">
      <div className="flex items-center gap-3">
        {cluster.representative_thumbnail_url ? (
          <img src={cluster.representative_thumbnail_url} alt="" className="h-14 w-14 rounded-md object-cover" />
        ) : (
          <div className="flex h-14 w-14 items-center justify-center rounded-md border border-zinc-700 text-xs text-zinc-500">
            Face
          </div>
        )}
        <div className="flex-1 space-y-2">
          <div className="text-xs uppercase tracking-[0.2em] text-zinc-500">{cluster.cluster_key}</div>
          <div className="grid grid-cols-2 gap-2">
            <input
              type="text"
              value={displayName}
              onChange={(event) => setDisplayName(event.target.value)}
              placeholder="Actor name"
              className="rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-sm text-zinc-100"
            />
            <input
              type="text"
              value={characterName}
              onChange={(event) => setCharacterName(event.target.value)}
              placeholder="Character"
              className="rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-sm text-zinc-100"
            />
          </div>
        </div>
        <button
          type="button"
          disabled={saving}
          className="rounded border border-zinc-700 px-2 py-1 text-xs text-zinc-100 hover:bg-zinc-900 disabled:opacity-50"
          onClick={async () => {
            try {
              setSaving(true)
              setError(null)
              await onSave(cluster, displayName, characterName)
            } catch (saveError) {
              setError(saveError instanceof Error ? saveError.message : 'Failed to save')
            } finally {
              setSaving(false)
            }
          }}
        >
          {saving ? 'Saving…' : 'Save'}
        </button>
      </div>
      {error ? <p className="mt-2 text-xs text-rose-300">{error}</p> : null}
    </div>
  )
}
