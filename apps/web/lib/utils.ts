import { type ClassValue, clsx } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

// NOTE: timecodeToSeconds and secondsToTimecode were removed from this file.
// Use the canonical implementations from '@/lib/timecode' which correctly handle
// non-integer frame rates (23.976, 29.97, 59.94 drop-frame).

export function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  const secs = Math.floor(seconds % 60)
  
  if (hours > 0) {
    return `${hours}h ${minutes}m ${secs}s`
  } else if (minutes > 0) {
    return `${minutes}m ${secs}s`
  } else {
    return `${secs}s`
  }
}

// File size utilities
export function formatFileSize(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let size = bytes
  let unitIndex = 0
  
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024
    unitIndex++
  }
  
  return `${size.toFixed(1)} ${units[unitIndex]}`
}

// Annotation utilities
export function getAnnotationColor(type: string): string {
  const normalizedType = type === 'voice' ? 'voice' : 'text'
  const colors = {
    text: '#3b82f6', // blue
    voice: '#10b981', // emerald
  }
  return colors[normalizedType]
}

export function getAnnotationIcon(type: string): string {
  const normalizedType = type === 'voice' ? 'voice' : 'text'
  const icons = {
    text: '💬',
    voice: '🎤',
  }
  return icons[normalizedType]
}

// URL utilities
export function getThumbnailUrl(proxyUrl: string): string {
  // Convert .m3u8 playlist URL to thumbnail URL
  return proxyUrl.replace('.m3u8', '_thumb.jpg')
}

// Validation utilities
export function isValidTimecode(timecode: string): boolean {
  const regex = /^(?:(?:[0-9]{2}:){2}[0-9]{2}[:;][0-9]{2})$/
  return regex.test(timecode)
}

export function isValidEmail(email: string): boolean {
  const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  return regex.test(email)
}

// Error handling
export class SlateError extends Error {
  constructor(
    message: string,
    public code?: string,
    public statusCode?: number
  ) {
    super(message)
    this.name = 'SlateError'
  }
}

// Local storage utilities
export const storage = {
  get: (key: string) => {
    if (typeof window === 'undefined') return null
    try {
      return JSON.parse(localStorage.getItem(key) || 'null')
    } catch {
      return null
    }
  },
  
  set: (key: string, value: any) => {
    if (typeof window === 'undefined') return
    try {
      localStorage.setItem(key, JSON.stringify(value))
    } catch {
      // Ignore errors
    }
  },
  
  remove: (key: string) => {
    if (typeof window === 'undefined') return
    localStorage.removeItem(key)
  }
}

// Debounce utility
export function debounce<T extends (...args: any[]) => void>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: NodeJS.Timeout | null = null
  
  return (...args: Parameters<T>) => {
    if (timeout) clearTimeout(timeout)
    timeout = setTimeout(() => func(...args), wait)
  }
}

// Throttle utility
export function throttle<T extends (...args: any[]) => void>(
  func: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle = false
  
  return (...args: Parameters<T>) => {
    if (!inThrottle) {
      func(...args)
      inThrottle = true
      setTimeout(() => inThrottle = false, limit)
    }
  }
}
