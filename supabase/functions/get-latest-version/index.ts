// Supabase Edge Function to get latest app version
// Used by appcast generator and for version checking

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create Supabase client (no auth required for public read)
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    )

    // Get the latest version (highest build number)
    const { data: latestVersion, error } = await supabaseClient
      .from('app_versions')
      .select('*')
      .order('build', { ascending: false })
      .limit(1)
      .single()

    if (error) {
      console.error('Error fetching latest version:', error)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch latest version', details: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!latestVersion) {
      return new Response(
        JSON.stringify({ error: 'No versions found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Return version information
    return new Response(
      JSON.stringify({
        version: latestVersion.version,
        build: latestVersion.build,
        release_notes: latestVersion.release_notes,
        zip_url: latestVersion.zip_url,
        dmg_url: latestVersion.dmg_url,
        release_date: latestVersion.release_date,
        is_required: latestVersion.is_required,
        min_os_version: latestVersion.min_os_version,
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Error in get-latest-version function:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

