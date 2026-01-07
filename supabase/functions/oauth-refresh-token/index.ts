// Supabase Edge Function to refresh OAuth tokens
// Reads provider configs from database, keeps client credentials secure in environment variables

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { getOAuthProvider, getClientId, getClientSecret, corsHeaders } from "../_shared/oauth-provider.ts"

interface RequestBody {
  provider: string
  refresh_token: string
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Parse request body
    const body: RequestBody = await req.json()
    const { provider, refresh_token } = body

    // Validate required fields
    if (!provider || !refresh_token) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: provider, refresh_token' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Fetch provider config from database
    const providerConfig = await getOAuthProvider(provider)
    if (!providerConfig) {
      return new Response(
        JSON.stringify({ error: `Invalid or disabled provider: ${provider}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get client credentials from environment
    const clientId = getClientId(provider)
    const clientSecret = getClientSecret(provider)

    if (!clientId || !clientSecret) {
      console.error(`Client credentials not configured for provider: ${provider}`)
      return new Response(
        JSON.stringify({ error: 'OAuth provider not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Refresh tokens
    const tokenParams = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refresh_token,
      client_id: clientId,
      client_secret: clientSecret,
    })

    console.log(`Refreshing token for provider: ${provider}`)

    const tokenResponse = await fetch(providerConfig.token_url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: tokenParams.toString(),
    })

    const tokenData = await tokenResponse.json()

    if (!tokenResponse.ok) {
      console.error(`Token refresh failed for ${provider}:`, tokenData)
      return new Response(
        JSON.stringify({
          error: 'Token refresh failed',
          details: tokenData.error_description || tokenData.error || 'Unknown error',
        }),
        { status: tokenResponse.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Token refresh successful for provider: ${provider}`)

    // Return the token response (contains access_token, possibly new refresh_token, expires_in, etc.)
    return new Response(
      JSON.stringify(tokenData),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error in oauth-refresh-token function:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
