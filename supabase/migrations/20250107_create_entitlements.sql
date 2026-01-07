-- Create tiered entitlement system
-- Migrates from simple is_premium boolean to flexible tier-based feature access

-- Subscription tiers lookup table
CREATE TABLE IF NOT EXISTS subscription_tiers (
    id TEXT PRIMARY KEY,  -- 'free', 'pro'
    display_name TEXT NOT NULL,
    priority INT NOT NULL DEFAULT 0,  -- For tier comparison (free=0, pro=100)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default tiers
INSERT INTO subscription_tiers (id, display_name, priority) VALUES
    ('free', 'Free', 0),
    ('pro', 'Pro', 100)
ON CONFLICT (id) DO NOTHING;

-- Features lookup table
CREATE TABLE IF NOT EXISTS features (
    id TEXT PRIMARY KEY,  -- Feature identifier matching Swift Feature enum rawValue
    display_name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert all features (matching Feature enum in FeatureEntitlementStore.swift)
INSERT INTO features (id, display_name, description) VALUES
    ('openai_llm', 'OpenAI GPT-4o', 'GPT-4o powered AI responses'),
    ('whisper_api', 'Cloud Transcription', 'Cloud-based speech transcription'),
    ('personalize', 'Personalization', 'Personalize your assistant'),
    ('mcp_integrations', 'Integrations', 'Connect Linear, Google Calendar, and more'),
    ('mcp_tool_calling', 'Tool Calling', 'AI tool integrations'),
    ('local_llm', 'Local AI', 'On-device AI processing')
ON CONFLICT (id) DO NOTHING;

-- Tier-to-features junction table
CREATE TABLE IF NOT EXISTS tier_features (
    tier_id TEXT REFERENCES subscription_tiers(id) ON DELETE CASCADE,
    feature_id TEXT REFERENCES features(id) ON DELETE CASCADE,
    PRIMARY KEY (tier_id, feature_id)
);

-- Free tier: local_llm only
INSERT INTO tier_features (tier_id, feature_id) VALUES
    ('free', 'local_llm')
ON CONFLICT DO NOTHING;

-- Pro tier: all features
INSERT INTO tier_features (tier_id, feature_id) VALUES
    ('pro', 'openai_llm'),
    ('pro', 'whisper_api'),
    ('pro', 'personalize'),
    ('pro', 'mcp_integrations'),
    ('pro', 'mcp_tool_calling'),
    ('pro', 'local_llm')
ON CONFLICT DO NOTHING;

-- Add tier_id column to profiles (backwards compatible - keeps is_premium)
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS tier_id TEXT REFERENCES subscription_tiers(id) DEFAULT 'free';

-- Migrate existing data: is_premium=true -> 'pro', false -> 'free'
UPDATE profiles
SET tier_id = CASE WHEN is_premium = true THEN 'pro' ELSE 'free' END
WHERE tier_id IS NULL OR tier_id = 'free';

-- Create function to get user entitlements with expiration handling
CREATE OR REPLACE FUNCTION get_user_entitlements(user_uuid UUID)
RETURNS JSON AS $$
DECLARE
    result JSON;
    effective_tier TEXT;
    is_expired BOOLEAN;
    expires_at TIMESTAMPTZ;
BEGIN
    -- Get profile and check expiration
    SELECT
        CASE
            WHEN p.premium_expires_at IS NOT NULL AND p.premium_expires_at < NOW()
            THEN 'free'
            ELSE COALESCE(p.tier_id, 'free')
        END,
        p.premium_expires_at IS NOT NULL AND p.premium_expires_at < NOW(),
        p.premium_expires_at
    INTO effective_tier, is_expired, expires_at
    FROM profiles p
    WHERE p.id = user_uuid;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    -- Build entitlements JSON with features as object
    SELECT json_build_object(
        'tier_id', effective_tier,
        'tier_name', st.display_name,
        'tier_priority', st.priority,
        'is_expired', is_expired,
        'expires_at', expires_at,
        'features', COALESCE(
            json_object_agg(tf.feature_id, true) FILTER (WHERE tf.feature_id IS NOT NULL),
            '{}'::json
        )
    )
    INTO result
    FROM subscription_tiers st
    LEFT JOIN tier_features tf ON tf.tier_id = st.id
    WHERE st.id = effective_tier
    GROUP BY st.id, st.display_name, st.priority;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission on the function
GRANT EXECUTE ON FUNCTION get_user_entitlements(UUID) TO authenticated;

-- Enable RLS on new tables
ALTER TABLE subscription_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE features ENABLE ROW LEVEL SECURITY;
ALTER TABLE tier_features ENABLE ROW LEVEL SECURITY;

-- Public read access for lookup tables (no sensitive data)
CREATE POLICY "Anyone can view subscription tiers"
ON subscription_tiers FOR SELECT
TO public
USING (true);

CREATE POLICY "Anyone can view features"
ON features FOR SELECT
TO public
USING (true);

CREATE POLICY "Anyone can view tier features"
ON tier_features FOR SELECT
TO public
USING (true);
