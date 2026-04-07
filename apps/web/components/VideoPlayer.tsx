'use client'

import React, { useEffect, useRef, useState, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import { Slider } from '@/components/ui/slider'
import { 
  Play, 
  Pause, 
  Volume2, 
  VolumeX, 
  Maximize2,
  SkipBack,
  SkipForward,
  Settings
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { secondsToTimecode, timecodeToSeconds } from '@/lib/timecode'
import type { Clip, Annotation } from '@/types'

interface VideoPlayerProps {
  clip: Clip | null
  token: string
  onTimeUpdate: (time: number) => void
  onPlay: () => void
  onPause: () => void
  annotations: Annotation[]
  onSeek: (time: number) => void
}

export const VideoPlayer = React.forwardRef<any, VideoPlayerProps>(({
  clip,
  token,
  onTimeUpdate,
  onPlay,
  onPause,
  annotations,
  onSeek
}, ref) => {
  const videoRef = useRef<HTMLVideoElement>(null)
  const hlsRef = useRef<any>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  
  const [isPlaying, setIsPlaying] = useState(false)
  const [currentTime, setCurrentTime] = useState(0)
  const [duration, setDuration] = useState(0)
  const [volume, setVolume] = useState(1)
  const [isMuted, setIsMuted] = useState(false)
  const [isBuffering, setIsBuffering] = useState(false)
  const [playbackRate, setPlaybackRate] = useState(1)
  const [showControls, setShowControls] = useState(true)
  const [proxyUrl, setProxyUrl] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  
  // Hide controls timer
  const controlsTimeoutRef = useRef<NodeJS.Timeout>()
  
  // Load HLS stream when clip changes
  useEffect(() => {
    if (!clip) return
    
    const loadVideo = async () => {
      try {
        setError(null)
        setIsBuffering(true)
        
        // Get signed URL for proxy
        const response = await fetch('/api/proxy-url', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Share-Token': token,
          },
          body: JSON.stringify({ clipId: clip.id }),
        })
        
        if (!response.ok) {
          throw new Error('Failed to load video')
        }
        
        const { signedUrl } = await response.json()
        setProxyUrl(signedUrl)
        
        // Initialize HLS.js if available
        if (window.Hls && videoRef.current) {
          if (hlsRef.current) {
            hlsRef.current.destroy()
          }
          
          const hls = new window.Hls({
            startLevel: -1, // Auto quality
            maxBufferLength: 30,
            maxMaxBufferLength: 600,
            maxBufferSize: 60 * 1000 * 1000, // 60 MB
            maxBufferHole: 0.5,
          })
          
          hls.loadSource(signedUrl)
          hls.attachMedia(videoRef.current)
          
          hls.on(window.Hls.Events.MANIFEST_PARSED, () => {
            setIsBuffering(false)
          })
          
          hls.on(window.Hls.Events.ERROR, (_event: unknown, data: { fatal?: boolean }) => {
            if (data.fatal) {
              setError('Failed to load video')
              setIsBuffering(false)
            }
          })
          
          hlsRef.current = hls
        } else if (videoRef.current) {
          // Native HLS support (Safari)
          videoRef.current.src = signedUrl
          setIsBuffering(false)
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unknown error')
        setIsBuffering(false)
      }
    }
    
    loadVideo()
    
    return () => {
      if (hlsRef.current) {
        hlsRef.current.destroy()
        hlsRef.current = null
      }
      if (controlsTimeoutRef.current) {
        clearTimeout(controlsTimeoutRef.current)
      }
    }
  }, [clip, token])
  
  // Update time
  const handleTimeUpdate = useCallback(() => {
    if (videoRef.current) {
      const time = videoRef.current.currentTime
      setCurrentTime(time)
      onTimeUpdate(time)
    }
  }, [onTimeUpdate])
  
  // Handle loaded metadata
  const handleLoadedMetadata = useCallback(() => {
    if (videoRef.current) {
      setDuration(videoRef.current.duration)
    }
  }, [])
  
  // Toggle play/pause
  const togglePlay = useCallback(() => {
    if (videoRef.current) {
      if (isPlaying) {
        videoRef.current.pause()
        onPause()
      } else {
        videoRef.current.play()
        onPlay()
      }
      setIsPlaying(!isPlaying)
    }
  }, [isPlaying, onPlay, onPause])
  
  // Handle seek
  const handleSeek = useCallback((value: number[]) => {
    const time = value[0]
    if (videoRef.current) {
      videoRef.current.currentTime = time
      setCurrentTime(time)
      onSeek(time)
    }
  }, [onSeek])
  
  // Handle volume change
  const handleVolumeChange = useCallback((value: number[]) => {
    const newVolume = value[0]
    setVolume(newVolume)
    if (videoRef.current) {
      videoRef.current.volume = newVolume
    }
  }, [])
  
  // Toggle mute
  const toggleMute = useCallback(() => {
    if (videoRef.current) {
      videoRef.current.muted = !isMuted
      setIsMuted(!isMuted)
    }
  }, [isMuted])
  
  // Skip forward/backward
  const skip = useCallback((seconds: number) => {
    if (videoRef.current) {
      videoRef.current.currentTime = Math.max(0, Math.min(duration, currentTime + seconds))
    }
  }, [currentTime, duration])
  
  // Toggle fullscreen
  const toggleFullscreen = useCallback(() => {
    if (containerRef.current) {
      if (document.fullscreenElement) {
        document.exitFullscreen()
      } else {
        containerRef.current.requestFullscreen()
      }
    }
  }, [])
  
  // Show/hide controls
  const handleMouseMove = useCallback(() => {
    setShowControls(true)
    
    if (controlsTimeoutRef.current) {
      clearTimeout(controlsTimeoutRef.current)
    }
    
    controlsTimeoutRef.current = setTimeout(() => {
      if (isPlaying) {
        setShowControls(false)
      }
    }, 3000)
  }, [isPlaying])
  
  // Format time
  const formatTime = (time: number) => {
    return secondsToTimecode(time, clip?.sourceFps || 24)
  }
  
  // Render annotation markers on scrub bar
  const renderAnnotationMarkers = () => {
    if (!clip || annotations.length === 0) return null
    
    return annotations.map((annotation) => {
      const seconds = timecodeToSeconds(annotation.timecodeIn, clip?.sourceFps || 24)
      const position = (seconds / duration) * 100
      
      return (
        <div
          key={annotation.id}
          className="absolute w-3 h-3 rounded-full transform -translate-x-1/2 -translate-y-1/2 cursor-pointer hover:scale-125 transition-transform"
          style={{
            left: `${position}%`,
            top: '50%',
            backgroundColor: getAnnotationColor(annotation.type),
          }}
          onClick={() => handleSeek([seconds])}
          title={`${annotation.type}: ${annotation.body}`}
        />
      )
    })
  }
  
  // Get annotation color — keys must match actual AnnotationType values ('text' | 'voice')
  function getAnnotationColor(type: string): string {
    const colors: Record<string, string> = {
      text: '#3b82f6',  // blue
      voice: '#10b981', // emerald
    }
    return colors[type] ?? '#64748b'
  }
  
  // Expose methods via ref
  React.useImperativeHandle(ref, () => ({
    load: () => {
      if (videoRef.current) {
        videoRef.current.load()
      }
    },
    get currentTime() {
      return videoRef.current?.currentTime || 0
    },
    set currentTime(time: number) {
      if (videoRef.current) {
        videoRef.current.currentTime = time
      }
    },
  }))
  
  if (!clip) {
    return (
      <div className="flex-1 flex items-center justify-center bg-black text-white">
        <p>Select a clip to play</p>
      </div>
    )
  }
  
  if (error) {
    return (
      <div className="flex-1 flex items-center justify-center bg-black text-white">
        <div className="text-center">
          <p className="text-red-500 mb-2">Error loading video</p>
          <p className="text-sm text-gray-400">{error}</p>
        </div>
      </div>
    )
  }
  
  return (
    <div 
      ref={containerRef}
      className="video-container flex-1 relative bg-black"
      onMouseMove={handleMouseMove}
      onMouseLeave={() => isPlaying && setShowControls(false)}
    >
      <video
        ref={videoRef}
        className="w-full h-full"
        onTimeUpdate={handleTimeUpdate}
        onLoadedMetadata={handleLoadedMetadata}
        onPlay={() => setIsPlaying(true)}
        onPause={() => setIsPlaying(false)}
        onWaiting={() => setIsBuffering(true)}
        onCanPlay={() => setIsBuffering(false)}
      />
      
      {/* Buffering indicator */}
      {isBuffering && (
        <div className="absolute inset-0 flex items-center justify-center bg-black/50">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
        </div>
      )}
      
      {/* Controls */}
      <div className={cn(
        "video-controls transition-opacity duration-300",
        showControls ? "opacity-100" : "opacity-0"
      )}>
        {/* Scrub bar */}
        <div className="relative mb-4">
          <Slider
            value={[currentTime]}
            max={duration || 100}
            step={1 / (clip?.sourceFps || 24)}
            onValueChange={handleSeek}
            className="w-full"
          />
          {/* Annotation markers */}
          <div className="absolute inset-0 pointer-events-none">
            {renderAnnotationMarkers()}
          </div>
        </div>
        
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            {/* Play/Pause */}
            <Button variant="ghost" size="sm" onClick={togglePlay} title="Play/Pause (K)">
              {isPlaying ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
            </Button>
            
            {/* Skip buttons */}
            <Button variant="ghost" size="sm" onClick={() => skip(-10)} title="Back 10s (J)">
              <SkipBack className="w-4 h-4" />
            </Button>
            <Button variant="ghost" size="sm" onClick={() => skip(10)} title="Forward 10s (L)">
              <SkipForward className="w-4 h-4" />
            </Button>
            
            {/* Time display */}
            <span className="text-sm font-mono text-white">
              {formatTime(currentTime)} / {formatTime(duration)}
            </span>
          </div>
          
          <div className="flex items-center gap-2">
            {/* Volume */}
            <Button variant="ghost" size="sm" onClick={toggleMute} title="Mute/unmute">
              {isMuted || volume === 0 ? (
                <VolumeX className="w-4 h-4" />
              ) : (
                <Volume2 className="w-4 h-4" />
              )}
            </Button>
            <Slider
              value={[isMuted ? 0 : volume]}
              max={1}
              step={0.1}
              onValueChange={handleVolumeChange}
              className="w-24"
            />
            
            {/* Playback rate */}
            <select
              value={playbackRate}
              onChange={(e) => {
                const rate = parseFloat(e.target.value)
                setPlaybackRate(rate)
                if (videoRef.current) {
                  videoRef.current.playbackRate = rate
                }
              }}
              className="bg-background border rounded px-2 py-1 text-sm"
              title="Playback speed"
            >
              <option value={0.5}>0.5x</option>
              <option value={1}>1x</option>
              <option value={1.5}>1.5x</option>
              <option value={2}>2x</option>
            </select>
            
            {/* Fullscreen */}
            <Button variant="ghost" size="sm" onClick={toggleFullscreen} title="Fullscreen">
              <Maximize2 className="w-4 h-4" />
            </Button>
          </div>
        </div>
      </div>
      
      {/* Click to play overlay */}
      {!isPlaying && (
        <div 
          className="absolute inset-0 flex items-center justify-center cursor-pointer"
          onClick={togglePlay}
        >
          <div className="bg-black/50 rounded-full p-4">
            <Play className="w-12 h-12 text-white" />
          </div>
        </div>
      )}
    </div>
  )
})

VideoPlayer.displayName = 'VideoPlayer'
