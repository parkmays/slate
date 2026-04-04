import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { cn } from '@/lib/utils'
import { HLSProvider } from '@/components/HLSProvider'
import { ErrorBoundary } from '@/components/ErrorBoundary'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'SLATE - Video Review & Collaboration',
  description: 'Professional video review and collaboration platform for film and TV production',
  icons: {
    icon: '/favicon.ico',
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className={cn(inter.className, "min-h-screen bg-background font-sans antialiased")}>
        <ErrorBoundary>
          <HLSProvider />
          {children}
        </ErrorBoundary>
      </body>
    </html>
  )
}