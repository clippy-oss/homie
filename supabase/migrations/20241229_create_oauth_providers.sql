-- Create oauth_providers table to store OAuth provider configurations
-- Client IDs and secrets are stored in Supabase Vault (environment variables), not in this table

CREATE TABLE IF NOT EXISTS oauth_providers (
    id TEXT PRIMARY KEY,                    -- e.g., "linear", "google_calendar"
    name TEXT NOT NULL,                     -- Display name: "Linear", "Google Calendar"
    auth_url TEXT NOT NULL,                 -- OAuth authorization endpoint
    token_url TEXT NOT NULL,                -- OAuth token endpoint
    scopes TEXT[] NOT NULL,                 -- Array of scopes to request
    scope_separator TEXT NOT NULL DEFAULT ' ', -- How to join scopes (space or comma)
    additional_params JSONB DEFAULT '{}',   -- Extra params like access_type, prompt
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default providers
INSERT INTO oauth_providers (id, name, auth_url, token_url, scopes, scope_separator, additional_params) VALUES
(
    'linear',
    'Linear',
    'https://linear.app/oauth/authorize',
    'https://api.linear.app/oauth/token',
    ARRAY['read', 'write'],
    ',',
    '{}'::jsonb
),
(
    'google_calendar',
    'Google Calendar',
    'https://accounts.google.com/o/oauth2/v2/auth',
    'https://oauth2.googleapis.com/token',
    ARRAY['https://www.googleapis.com/auth/calendar.events'],
    ' ',
    '{"access_type": "offline", "prompt": "consent"}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    auth_url = EXCLUDED.auth_url,
    token_url = EXCLUDED.token_url,
    scopes = EXCLUDED.scopes,
    scope_separator = EXCLUDED.scope_separator,
    additional_params = EXCLUDED.additional_params,
    updated_at = NOW();

-- Enable RLS
ALTER TABLE oauth_providers ENABLE ROW LEVEL SECURITY;

-- Allow public read access (configs are not sensitive, secrets are in env vars)
CREATE POLICY "Allow public read access to oauth_providers"
ON oauth_providers FOR SELECT
TO public
USING (is_enabled = true);

-- Only service role can modify
CREATE POLICY "Service role can manage oauth_providers"
ON oauth_providers FOR ALL
TO service_role
USING (true);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_oauth_providers_enabled ON oauth_providers(id) WHERE is_enabled = true;
