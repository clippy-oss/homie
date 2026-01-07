// Shared module for fetching OAuth provider configurations from the database

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export interface OAuthProvider {
  id: string
  name: string
  auth_url: string
  token_url: string
  scopes: string[]
  scope_separator: string
  additional_params: Record<string, string>
  is_enabled: boolean
}

/**
 * Fetches an OAuth provider configuration from the database
 * @param providerId - The provider ID (e.g., "linear", "google_calendar")
 * @returns The provider configuration or null if not found
 */
export async function getOAuthProvider(providerId: string): Promise<OAuthProvider | null> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const supabase = createClient(supabaseUrl, supabaseServiceKey)

  const { data, error } = await supabase
    .from('oauth_providers')
    .select('*')
    .eq('id', providerId)
    .eq('is_enabled', true)
    .single()

  if (error) {
    console.error(`Error fetching provider ${providerId}:`, error)
    return null
  }

  return data as OAuthProvider
}

/**
 * Gets the client ID for a provider from environment variables
 * @param providerId - The provider ID
 * @returns The client ID or null if not configured
 */
export function getClientId(providerId: string): string | null {
  const envVarName = `${providerId.toUpperCase()}_CLIENT_ID`
  return Deno.env.get(envVarName) || null
}

/**
 * Gets the client secret for a provider from environment variables
 * @param providerId - The provider ID
 * @returns The client secret or null if not configured
 */
export function getClientSecret(providerId: string): string | null {
  const envVarName = `${providerId.toUpperCase()}_CLIENT_SECRET`
  return Deno.env.get(envVarName) || null
}

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
