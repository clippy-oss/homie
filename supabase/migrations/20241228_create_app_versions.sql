-- Create app_versions table to track macOS app releases for Sparkle updates

CREATE TABLE IF NOT EXISTS app_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version TEXT NOT NULL UNIQUE,
    build INTEGER NOT NULL UNIQUE,
    release_notes TEXT,
    zip_url TEXT NOT NULL,
    dmg_url TEXT,
    release_date TIMESTAMPTZ DEFAULT NOW(),
    is_required BOOLEAN DEFAULT false,
    min_os_version TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE app_versions ENABLE ROW LEVEL SECURITY;

-- Allow public read access (version info is not sensitive)
CREATE POLICY "Allow public read access to app_versions"
ON app_versions FOR SELECT
TO public
USING (true);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_app_versions_build ON app_versions(build DESC);
CREATE INDEX IF NOT EXISTS idx_app_versions_release_date ON app_versions(release_date DESC);
