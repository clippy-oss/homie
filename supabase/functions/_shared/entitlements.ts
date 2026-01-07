// Shared entitlements utility for Edge Functions
// Provides centralized entitlement checking logic

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Feature IDs matching the database and Swift Feature enum
export type FeatureId =
  | 'openai_llm'
  | 'whisper_api'
  | 'personalize'
  | 'mcp_integrations'
  | 'mcp_tool_calling'
  | 'local_llm';

export interface UserEntitlements {
  tier_id: string;
  tier_name: string;
  tier_priority: number;
  is_expired: boolean;
  expires_at: string | null;
  features: Record<string, boolean>;
}

export interface EntitlementCheckResult {
  success: boolean;
  entitlements?: UserEntitlements;
  error?: string;
  status?: number;
}

/**
 * Get user entitlements using the database function
 */
export async function getUserEntitlements(
  supabaseClient: SupabaseClient,
  userId: string
): Promise<EntitlementCheckResult> {
  const { data, error } = await supabaseClient
    .rpc('get_user_entitlements', { user_uuid: userId });

  if (error) {
    console.error('Error fetching entitlements:', error);
    return {
      success: false,
      error: 'Failed to fetch entitlements',
      status: 500
    };
  }

  if (!data) {
    return {
      success: false,
      error: 'User profile not found',
      status: 404
    };
  }

  return {
    success: true,
    entitlements: data as UserEntitlements
  };
}

/**
 * Check if user has access to a specific feature
 */
export function hasFeature(
  entitlements: UserEntitlements,
  featureId: FeatureId
): boolean {
  return entitlements.features[featureId] === true;
}

/**
 * Check if user has pro-level access (for legacy is_premium compatibility)
 */
export function isPro(entitlements: UserEntitlements): boolean {
  return entitlements.tier_id === 'pro' && !entitlements.is_expired;
}

/**
 * Require a specific feature, returning error response if not available
 *
 * Usage:
 * ```ts
 * const { allowed, response, entitlements } = await requireFeature(
 *   supabaseClient, user.id, 'openai_llm', corsHeaders
 * );
 * if (!allowed) return response!;
 * // Continue with feature...
 * ```
 */
export async function requireFeature(
  supabaseClient: SupabaseClient,
  userId: string,
  featureId: FeatureId,
  corsHeaders: Record<string, string>
): Promise<{
  allowed: boolean;
  response?: Response;
  entitlements?: UserEntitlements;
}> {
  const result = await getUserEntitlements(supabaseClient, userId);

  if (!result.success) {
    return {
      allowed: false,
      response: new Response(
        JSON.stringify({ error: result.error }),
        {
          status: result.status || 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    };
  }

  const entitlements = result.entitlements!;

  if (!hasFeature(entitlements, featureId)) {
    return {
      allowed: false,
      response: new Response(
        JSON.stringify({
          error: 'Feature not available',
          required_feature: featureId,
          current_tier: entitlements.tier_id,
          upgrade_required: true
        }),
        {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    };
  }

  return {
    allowed: true,
    entitlements
  };
}

/**
 * Build response with entitlements for get-user-status endpoint
 * Includes backwards compatibility with is_premium field
 */
export function buildEntitlementsResponse(
  userId: string,
  email: string,
  entitlements: UserEntitlements
): object {
  return {
    user_id: userId,
    email: email,
    // New structured entitlements
    entitlements: entitlements,
    // Backwards compatibility
    is_premium: isPro(entitlements),
    premium_expires_at: entitlements.expires_at
  };
}
