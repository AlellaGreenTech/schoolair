-- SchoolAir Sponsors Table
-- Run this in Supabase SQL Editor

CREATE TABLE schoolair_sponsors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ,
  email TEXT NOT NULL,
  display_name TEXT,                -- "Harry & Sally Brooks"
  dedication TEXT,                  -- "For Ms. Garcia's 3rd grade class"
  sponsor_type TEXT NOT NULL CHECK (sponsor_type IN ('sponsor', 'patron')),
  kit_type TEXT CHECK (kit_type IN ('home_build', 'installed')),  -- null for patrons
  tier INTEGER CHECK (tier IN (5, 10, 25)),                      -- null for sponsors
  amount INTEGER NOT NULL,          -- in cents (6500 = €65)
  currency TEXT NOT NULL DEFAULT 'eur',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled', 'refunded')),
  stripe_session_id TEXT,
  stripe_payment_id TEXT,           -- payment_intent for sponsors, subscription_id for patrons
  label_confirmed BOOLEAN NOT NULL DEFAULT false,
  label_token UUID DEFAULT gen_random_uuid()  -- secret token for edit-label URL
);

-- For the sponsors wall query
CREATE INDEX idx_schoolair_sponsors_wall ON schoolair_sponsors (status, created_at DESC);

-- For label edit lookups
CREATE INDEX idx_schoolair_sponsors_token ON schoolair_sponsors (label_token);

-- RLS
ALTER TABLE schoolair_sponsors ENABLE ROW LEVEL SECURITY;

-- Public can read completed sponsors (for the wall)
CREATE POLICY "Public can read completed sponsors"
  ON schoolair_sponsors FOR SELECT
  USING (status = 'completed');

-- Service role bypasses RLS automatically (used by Edge Functions)

-- RPC Function: get_schoolair_progress
CREATE OR REPLACE FUNCTION get_schoolair_progress()
RETURNS JSON AS $$
  SELECT json_build_object(
    'protected', (
      SELECT COUNT(*)::int
      FROM schoolair_sponsors
      WHERE status = 'completed' AND sponsor_type = 'sponsor'
    ) + 2,  -- 2 existing sensors already installed
    'total', 48
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;
