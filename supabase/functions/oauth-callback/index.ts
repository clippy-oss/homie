// Supabase Edge Function to handle OAuth callbacks from providers like Google
// Receives the authorization code and redirects to the native app with the code

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

// Map provider IDs to their app redirect paths
const providerRedirectPaths: Record<string, string> = {
  'google_calendar': 'oauth/google',
  'linear': 'oauth/linear',
}

serve(async (req) => {
  const url = new URL(req.url)

  // Extract OAuth callback parameters
  const code = url.searchParams.get('code')
  const state = url.searchParams.get('state')
  const error = url.searchParams.get('error')
  const errorDescription = url.searchParams.get('error_description')

  console.log('OAuth callback received:', {
    hasCode: !!code,
    hasState: !!state,
    error,
    errorDescription
  })

  // State format: "providerId:originalState" (e.g., "google_calendar:abc123xyz")
  let provider = 'google_calendar' // default
  let originalState = state

  if (state && state.includes(':')) {
    const colonIndex = state.indexOf(':')
    provider = state.substring(0, colonIndex)
    originalState = state.substring(colonIndex + 1)
  }

  // Get the redirect path for this provider
  const redirectPath = providerRedirectPaths[provider] || 'oauth/callback'

  // Build the app redirect URL
  const appURL = new URL(`homie://${redirectPath}`)

  if (code) {
    appURL.searchParams.set('code', code)
  }
  if (originalState) {
    appURL.searchParams.set('state', originalState)
  }
  if (error) {
    appURL.searchParams.set('error', error)
  }
  if (errorDescription) {
    appURL.searchParams.set('error_description', errorDescription)
  }

  console.log(`Redirecting to app: ${appURL.toString()}`)

  // Return an HTML page that redirects to the app
  // This is more reliable than a 302 redirect for custom URL schemes
  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Redirecting to Homie...</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
    }
    .container {
      text-align: center;
      padding: 2rem;
    }
    h1 { margin-bottom: 1rem; }
    p { opacity: 0.9; }
    a {
      display: inline-block;
      margin-top: 1rem;
      padding: 0.75rem 1.5rem;
      background: white;
      color: #667eea;
      text-decoration: none;
      border-radius: 8px;
      font-weight: 600;
    }
    a:hover { opacity: 0.9; }
  </style>
</head>
<body>
  <div class="container">
    <h1>${error ? 'Authentication Failed' : 'Authentication Successful!'}</h1>
    <p>${error ? errorDescription || error : 'Redirecting you back to Homie...'}</p>
    <a href="${appURL.toString()}">Open Homie</a>
  </div>
  <script>
    // Automatically redirect to the app
    window.location.href = "${appURL.toString()}";
  </script>
</body>
</html>
`

  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
    },
  })
})
