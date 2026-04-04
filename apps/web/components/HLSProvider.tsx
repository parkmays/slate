'use client'

import { useEffect } from 'react'

export function HLSProvider() {
  useEffect(() => {
    // Load HLS.js script
    const script = document.createElement('script')
    script.src = 'https://cdn.jsdelivr.net/npm/hls.js@latest'
    script.async = true
    
    script.onload = () => {
      console.log('HLS.js loaded')
    }
    
    document.head.appendChild(script)
    
    return () => {
      // Clean up
      if (document.head.contains(script)) {
        document.head.removeChild(script)
      }
    }
  }, [])
  
  return null
}