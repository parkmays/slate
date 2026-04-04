#!/bin/bash

# SLATE Web Development Script
# Starts the web portal with all necessary services

echo "🚀 Starting SLATE Web Portal..."

# Check if .env.local exists
if [ ! -f "apps/web/.env.local" ]; then
    echo "⚠️  .env.local not found. Copying from .env.example..."
    cp apps/web/.env.example apps/web/.env.local
    echo "✅ Please edit apps/web/.env.local with your configuration"
    echo ""
fi

# Check if Supabase is running
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found. Please install it first:"
    echo "   brew install supabase/tap/supabase"
    exit 1
fi

# Start Supabase if not running
if ! supabase status &> /dev/null; then
    echo "📦 Starting Supabase..."
    cd supabase
    supabase start
    cd ..
fi

# Get Supabase URLs
SUPABASE_URL=$(supabase status | grep "API URL" | awk '{print $3}')
SUPABASE_ANON_KEY=$(supabase status | grep "anon key" | awk '{print $3}')

echo "🔗 Supabase URL: $SUPABASE_URL"
echo "🔑 Anon Key: $SUPABASE_ANON_KEY"

# Update .env.local with Supabase values
sed -i '' "s|NEXT_PUBLIC_SUPABASE_URL=.*|NEXT_PUBLIC_SUPABASE_URL=$SUPABASE_URL|" apps/web/.env.local
sed -i '' "s|NEXT_PUBLIC_SUPABASE_ANON_KEY=.*|NEXT_PUBLIC_SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY|" apps/web/.env.local

# Install dependencies if needed
if [ ! -d "apps/web/node_modules" ]; then
    echo "📦 Installing dependencies..."
    cd apps/web
    npm install
    cd ../..
fi

# Start the web portal
echo "🌐 Starting web portal..."
cd apps/web
npm run dev