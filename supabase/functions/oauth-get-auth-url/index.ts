// Supabase Edge Function to generate OAuth authorization URLs
// Reads provider configs from database, keeps client_id secure in environment variables

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { getOAuthProvider, getClientId, corsHeaders } from "../_shared/oauth-provider.ts"

interface RequestBody {
  provider: string
  redirect_uri: string
  state: string
}

// Providers that require server-side callback (don't support custom URL schemes)
const providersRequiringServerCallback = ['google_calendar']

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Parse request body
    const body: RequestBody = await req.json()
    const { provider, redirect_uri, state } = body

    // Validate required fields
    if (!provider || !redirect_uri || !state) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: provider, redirect_uri, state' }),
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

    // Get client_id from environment
    const clientId = getClientId(provider)
    if (!clientId) {
      console.error(`Client ID not configured for provider: ${provider}`)
      return new Response(
        JSON.stringify({ error: 'OAuth provider not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Determine the actual redirect URI to use
    // For providers like Google that don't support custom URL schemes,
    // use our server-side callback that will redirect to the app
    let actualRedirectUri = redirect_uri
    let actualState = state

    if (providersRequiringServerCallback.includes(provider)) {
      // Use the Supabase callback URL
      const supabaseUrl = Deno.env.get('SUPABASE_URL')!
      actualRedirectUri = `${supabaseUrl}/functions/v1/oauth-callback`
      // Encode the provider in the state so the callback knows where to redirect
      // Format: "providerId:originalState"
      actualState = `${provider}:${state}`
      console.log(`Using server callback for ${provider}: ${actualRedirectUri}`)
    }

    // Build authorization URL
    const params = new URLSearchParams({
      client_id: clientId,
      redirect_uri: actualRedirectUri,
      state: actualState,
      response_type: 'code',
      scope: providerConfig.scopes.join(providerConfig.scope_separator),
      ...providerConfig.additional_params,
    })

    const authUrl = `${providerConfig.auth_url}?${params.toString()}`

    console.log(`Generated auth URL for provider: ${provider}`)

    // Return both the auth URL and the actual redirect URI used
    // (client needs this for token exchange)
    return new Response(
      JSON.stringify({
        auth_url: authUrl,
        redirect_uri: actualRedirectUri,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error in oauth-get-auth-url function:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
