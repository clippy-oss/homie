// Supabase Edge Function for Deepgram streaming STT
// Proxies WebSocket connection to Deepgram, keeps API key secure on server
// Premium users only - validates JWT and subscription status

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { requireFeature } from '../_shared/entitlements.ts'

const DEEPGRAM_API_KEY = Deno.env.get('DEEPGRAM_API_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, upgrade, connection, sec-websocket-key, sec-websocket-version, sec-websocket-protocol',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Check for WebSocket upgrade
  const upgrade = req.headers.get("upgrade") || ""
  if (upgrade.toLowerCase() !== "websocket") {
    return new Response(
      JSON.stringify({ error: 'Expected WebSocket upgrade request' }),
      { status: 426, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  try {
    // 1. Validate user authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'No authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Create Supabase client to verify user
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    // 3. Get the authenticated user
    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser()

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 4. Check if user has access to Whisper API feature (covers all cloud transcription)
    const { allowed, response } = await requireFeature(
      supabaseClient,
      user.id,
      'whisper_api',
      corsHeaders
    )

    if (!allowed) {
      return response!
    }

    // 5. Check Deepgram API key is configured
    if (!DEEPGRAM_API_KEY) {
      console.error('DEEPGRAM_API_KEY not configured')
      return new Response(
        JSON.stringify({ error: 'Service configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 6. Upgrade to WebSocket
    const { socket: clientSocket, response } = Deno.upgradeWebSocket(req)

    // 7. Connect to Deepgram when client connects
    clientSocket.onopen = () => {
      console.log('Client connected, establishing Deepgram connection...')

      // Build Deepgram WebSocket URL with parameters
      const deepgramUrl = new URL("wss://api.deepgram.com/v1/listen")
      deepgramUrl.searchParams.set("model", "nova-2")
      deepgramUrl.searchParams.set("language", "en")
      deepgramUrl.searchParams.set("encoding", "linear16")
      deepgramUrl.searchParams.set("sample_rate", "16000")
      deepgramUrl.searchParams.set("channels", "1")
      deepgramUrl.searchParams.set("punctuate", "true")
      deepgramUrl.searchParams.set("interim_results", "true")
      deepgramUrl.searchParams.set("endpointing", "300")
      deepgramUrl.searchParams.set("vad_events", "true")

      // Connect to Deepgram with API key
      const deepgramSocket = new WebSocket(deepgramUrl.toString(), [
        "token",
        DEEPGRAM_API_KEY
      ])

      // Bridge client -> Deepgram (audio data)
      clientSocket.onmessage = (event) => {
        if (deepgramSocket.readyState === WebSocket.OPEN) {
          // Forward audio data to Deepgram
          deepgramSocket.send(event.data)
        }
      }

      // Bridge Deepgram -> client (transcription results)
      deepgramSocket.onmessage = (event) => {
        if (clientSocket.readyState === WebSocket.OPEN) {
          // Forward transcription results to client
          clientSocket.send(event.data)
        }
      }

      deepgramSocket.onopen = () => {
        console.log('Connected to Deepgram')
        // Notify client that we're ready
        if (clientSocket.readyState === WebSocket.OPEN) {
          clientSocket.send(JSON.stringify({ type: 'ready' }))
        }
      }

      deepgramSocket.onerror = (error) => {
        console.error('Deepgram WebSocket error:', error)
        if (clientSocket.readyState === WebSocket.OPEN) {
          clientSocket.send(JSON.stringify({
            type: 'error',
            message: 'Deepgram connection error'
          }))
        }
      }

      deepgramSocket.onclose = (event) => {
        console.log('Deepgram connection closed:', event.code, event.reason)
        if (clientSocket.readyState === WebSocket.OPEN) {
          clientSocket.close(1000, 'Deepgram connection closed')
        }
      }

      // Clean up Deepgram connection when client disconnects
      clientSocket.onclose = () => {
        console.log('Client disconnected')
        if (deepgramSocket.readyState === WebSocket.OPEN ||
            deepgramSocket.readyState === WebSocket.CONNECTING) {
          deepgramSocket.close()
        }
      }

      clientSocket.onerror = (error) => {
        console.error('Client WebSocket error:', error)
        if (deepgramSocket.readyState === WebSocket.OPEN) {
          deepgramSocket.close()
        }
      }
    }

    return response

  } catch (error) {
    console.error('Error in stream-transcribe-deepgram function:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
