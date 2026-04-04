'use client'

import React from 'react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

interface RequestAlternateButtonProps {
  disabled?: boolean
  onSubmit: (note: string) => Promise<void> | void
}

const TEMPLATE_NOTES = [
  'Need a cleaner performance alt.',
  'Looking for a sharper focus option.',
  'Need an alternate with cleaner audio.',
  'Please pull a wider framing option.',
]

export function RequestAlternateButton({
  disabled = false,
  onSubmit,
}: RequestAlternateButtonProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [note, setNote] = useState('')

  async function handleSubmit() {
    const trimmed = note.trim()
    if (!trimmed || disabled) {
      return
    }

    await onSubmit(trimmed)
    setNote('')
    setIsOpen(false)
  }

  return (
    <div className="space-y-2">
      <Button
        type="button"
        variant="outline"
        onClick={() => setIsOpen((open) => !open)}
      >
        Request Alt
      </Button>

      {isOpen && (
        <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-3 shadow-xl">
          <div className="space-y-3">
            <label className="block text-xs font-semibold uppercase tracking-[0.22em] text-zinc-500">
              Describe what you need…
            </label>
            <div className="flex flex-wrap gap-2">
              {TEMPLATE_NOTES.map((template) => (
                <Button
                  key={template}
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => setNote(template)}
                  className="border-zinc-700 bg-zinc-950 text-zinc-300 hover:bg-zinc-900"
                >
                  {template}
                </Button>
              ))}
            </div>
            <Input
              value={note}
              onChange={(event) => setNote(event.target.value)}
              placeholder="Describe what you need…"
            />
            <div className="flex justify-end gap-2">
              <Button type="button" variant="ghost" onClick={() => setIsOpen(false)}>
                Cancel
              </Button>
              <Button type="button" onClick={() => void handleSubmit()} disabled={!note.trim() || disabled}>
                Submit
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
