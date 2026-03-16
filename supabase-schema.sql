-- ============================================================================
-- FARMHACK SUPABASE SCHEMA v1
-- Tuckaway Farm / Wentworth Hunt — Multi-site auth + documents + media
--
-- Run this in your Supabase project: SQL Editor → New query → paste → Run
-- ============================================================================

-- ── Extensions ───────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- fuzzy name search

-- ── Enums ────────────────────────────────────────────────────────────────────
CREATE TYPE farm_role AS ENUM (
  'super_admin',   -- full access to all sites + billing
  'admin',         -- full access to their site(s)
  'manager',       -- edit data, run sync, manage members
  'member',        -- log chores, add notes, view all
  'guest',         -- view only
  'pending'        -- awaiting approval
);

CREATE TYPE member_type AS ENUM (
  'owner', 'boarder', 'rider', 'staff',
  'hunter', 'hunt_member', 'volunteer', 'guest'
);

CREATE TYPE doc_type AS ENUM (
  'liability_release',
  'boarding_agreement',
  'facilities_waiver',
  'hunt_membership',
  'hunter_release',
  'volunteer_agreement',
  'coop_agreement'
);

CREATE TYPE farm_site AS ENUM ('barn', 'kennel', 'hunters', 'all');

CREATE TYPE media_kind AS ENUM ('photo', 'video', 'audio', 'document', 'gpx');

-- ── profiles ─────────────────────────────────────────────────────────────────
-- One row per authenticated user. Created automatically on first login.
CREATE TABLE profiles (
  id                UUID        REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email             TEXT        NOT NULL,
  full_name         TEXT,
  display_name      TEXT,                        -- shorter name for UI
  role              farm_role   NOT NULL DEFAULT 'pending',
  member_type       member_type DEFAULT 'guest',
  -- Per-site role overrides (JSON map: {barn: 'manager', kennel: 'member', hunters: 'admin'})
  -- If a site key is absent, falls back to the top-level `role` field
  site_access       JSONB       NOT NULL DEFAULT '{}'::jsonb,
  -- Contact
  phone             TEXT,
  address           TEXT,
  -- Emergency
  emergency_name    TEXT,
  emergency_phone   TEXT,
  emergency_relation TEXT,
  medical_notes     TEXT,
  -- Farm-specific
  vehicle           TEXT,
  trailer           TEXT,
  farmos_uuid       TEXT,                        -- linked farmOS user UUID
  -- Meta
  avatar_url        TEXT,
  notes             TEXT,
  is_active         BOOLEAN     NOT NULL DEFAULT true,
  approved_by       UUID        REFERENCES profiles(id),
  approved_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Trigger: auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── site_config ───────────────────────────────────────────────────────────────
-- Stores per-site settings that admins can set from the admin page
CREATE TABLE site_config (
  id        UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  site      farm_site   NOT NULL,
  key       TEXT        NOT NULL,
  value     JSONB,
  updated_by UUID       REFERENCES profiles(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (site, key)
);

-- ── documents ────────────────────────────────────────────────────────────────
-- Signed agreements, waivers, and releases
CREATE TABLE documents (
  id              UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id         UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  site            farm_site   NOT NULL,
  doc_type        doc_type    NOT NULL,
  season          TEXT,                  -- e.g. "2025-2026", "2026"
  -- Signature
  signed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  signature_data  TEXT,                  -- base64 dataURL of canvas signature
  acknowledgments JSONB,                 -- [{key, label, checked}]
  signer_name     TEXT,                  -- printed name at signing
  signer_ip       TEXT,
  signer_ua       TEXT,
  -- Storage
  pdf_url         TEXT,                  -- Supabase Storage path or external URL
  -- Status
  is_valid        BOOLEAN     NOT NULL DEFAULT true,
  voided_at       TIMESTAMPTZ,
  voided_by       UUID        REFERENCES profiles(id),
  void_reason     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX documents_user_site ON documents(user_id, site);
CREATE INDEX documents_season    ON documents(season);

-- ── media ─────────────────────────────────────────────────────────────────────
-- Photos, videos, audio recordings linked to any entity in any site
CREATE TABLE media (
  id              UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  uploaded_by     UUID        REFERENCES profiles(id) ON DELETE SET NULL,
  site            farm_site   NOT NULL,
  -- What this media is attached to
  entity_type     TEXT,          -- 'horse','hound','hunter','log','note','event','tool_doc','stand'
  entity_id       TEXT,          -- local ID or farmOS UUID
  entity_name     TEXT,          -- denormalized for display
  -- File info
  kind            media_kind  NOT NULL DEFAULT 'photo',
  storage_path    TEXT        NOT NULL, -- Supabase storage bucket path OR external URL
  storage_backend TEXT        NOT NULL DEFAULT 'supabase', -- 'supabase' | 'minio' | 'r2' | 'external'
  filename        TEXT,
  mime_type       TEXT,
  size_bytes      BIGINT,
  -- Media metadata
  duration_secs   INTEGER,                      -- audio/video
  width_px        INTEGER,                      -- photo/video
  height_px       INTEGER,
  gps_lat         DOUBLE PRECISION,             -- from EXIF or manual
  gps_lng         DOUBLE PRECISION,
  recorded_at     TIMESTAMPTZ,                  -- actual capture time
  -- Display
  caption         TEXT,
  tags            TEXT[],
  is_public       BOOLEAN     NOT NULL DEFAULT false,
  is_flagged      BOOLEAN     NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX media_entity   ON media(entity_type, entity_id);
CREATE INDEX media_site     ON media(site);
CREATE INDEX media_uploaded ON media(uploaded_by);

-- ── audit_log ─────────────────────────────────────────────────────────────────
-- Lightweight audit trail for sensitive actions
CREATE TABLE audit_log (
  id          UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id     UUID        REFERENCES profiles(id) ON DELETE SET NULL,
  site        farm_site,
  action      TEXT        NOT NULL,  -- 'sign_document','approve_member','push_farmos',etc.
  entity_type TEXT,
  entity_id   TEXT,
  details     JSONB,
  ip          TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── invitations ───────────────────────────────────────────────────────────────
-- Admin sends invite links; recipient clicks to create account
CREATE TABLE invitations (
  id          UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  email       TEXT        NOT NULL,
  site        farm_site   NOT NULL DEFAULT 'all',
  role        farm_role   NOT NULL DEFAULT 'member',
  member_type member_type DEFAULT 'guest',
  invited_by  UUID        NOT NULL REFERENCES profiles(id),
  token       UUID        NOT NULL DEFAULT uuid_generate_v4(),
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
  accepted_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(email)
);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE media          ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log      ENABLE ROW LEVEL SECURITY;
ALTER TABLE site_config    ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitations    ENABLE ROW LEVEL SECURITY;

-- ── Helper: get current user role ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS farm_role AS $$
  SELECT role FROM profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION current_user_site_role(p_site TEXT)
RETURNS TEXT AS $$
  SELECT COALESCE(
    site_access ->> p_site,
    role::text
  )
  FROM profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT role IN ('admin','super_admin') FROM profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ── profiles policies ─────────────────────────────────────────────────────────
-- Everyone can read all active profiles (needed for member directories)
CREATE POLICY "profiles_select_active"
  ON profiles FOR SELECT
  USING (is_active = true OR id = auth.uid());

-- Users can update their own non-role fields
CREATE POLICY "profiles_update_own"
  ON profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (
    id = auth.uid()
    AND role = (SELECT role FROM profiles WHERE id = auth.uid())  -- can't self-promote
  );

-- Admins can update any profile (including role changes)
CREATE POLICY "profiles_update_admin"
  ON profiles FOR UPDATE
  USING (is_admin());

-- New users can insert their own profile (on first login)
CREATE POLICY "profiles_insert_own"
  ON profiles FOR INSERT
  WITH CHECK (id = auth.uid());

-- ── documents policies ────────────────────────────────────────────────────────
-- Users can read their own docs; admins/managers read all
CREATE POLICY "documents_select"
  ON documents FOR SELECT
  USING (
    user_id = auth.uid()
    OR current_user_role() IN ('admin', 'super_admin', 'manager')
  );

-- Users can insert their own docs
CREATE POLICY "documents_insert_own"
  ON documents FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Admins can void/update docs
CREATE POLICY "documents_update_admin"
  ON documents FOR UPDATE
  USING (is_admin());

-- ── media policies ────────────────────────────────────────────────────────────
CREATE POLICY "media_select"
  ON media FOR SELECT
  USING (
    is_public = true
    OR uploaded_by = auth.uid()
    OR current_user_role() IN ('admin','super_admin','manager','member')
  );

CREATE POLICY "media_insert"
  ON media FOR INSERT
  WITH CHECK (
    uploaded_by = auth.uid()
    AND current_user_role() IN ('admin','super_admin','manager','member')
  );

CREATE POLICY "media_delete"
  ON media FOR DELETE
  USING (uploaded_by = auth.uid() OR is_admin());

-- ── audit_log policies ────────────────────────────────────────────────────────
CREATE POLICY "audit_select_admin"
  ON audit_log FOR SELECT
  USING (is_admin());

CREATE POLICY "audit_insert_any_auth"
  ON audit_log FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- ── site_config policies ──────────────────────────────────────────────────────
CREATE POLICY "config_select_all"
  ON site_config FOR SELECT
  USING (true);

CREATE POLICY "config_mutate_admin"
  ON site_config FOR ALL
  USING (is_admin());

-- ── invitations policies ──────────────────────────────────────────────────────
CREATE POLICY "invitations_select_admin"
  ON invitations FOR SELECT
  USING (is_admin() OR email = (SELECT email FROM auth.users WHERE id = auth.uid()));

CREATE POLICY "invitations_insert_admin"
  ON invitations FOR INSERT
  WITH CHECK (is_admin());

-- ============================================================================
-- SUPABASE STORAGE BUCKETS (run after enabling Storage in your project)
-- ============================================================================
-- Run these in the SQL editor OR via the Storage tab in Supabase dashboard

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  -- Farm media (photos, video, audio) — private, served via signed URL
  ('farm-media', 'farm-media', false, 104857600,   -- 100 MB max per file
   ARRAY['image/jpeg','image/png','image/webp','image/gif',
         'video/mp4','video/quicktime','video/webm',
         'audio/mpeg','audio/wav','audio/ogg','audio/mp4',
         'application/gpx+xml','text/xml']),
  -- Signed documents (PDF exports) — private
  ('farm-docs',  'farm-docs',  false, 20971520,    -- 20 MB max
   ARRAY['application/pdf','image/png','image/jpeg']),
  -- Public farm assets (logos, hero images) — public CDN
  ('farm-public','farm-public', true, 5242880,
   ARRAY['image/jpeg','image/png','image/webp','image/svg+xml'])
ON CONFLICT (id) DO NOTHING;

-- Storage RLS
CREATE POLICY "farm_media_auth_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'farm-media' AND auth.uid() IS NOT NULL);

CREATE POLICY "farm_media_auth_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'farm-media' AND auth.uid() IS NOT NULL
              AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "farm_docs_auth_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'farm-docs' AND auth.uid() IS NOT NULL);

CREATE POLICY "farm_docs_auth_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'farm-docs' AND auth.uid() IS NOT NULL);

CREATE POLICY "farm_public_all_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'farm-public');

-- ============================================================================
-- SEED: default site config
-- ============================================================================
INSERT INTO site_config (site, key, value) VALUES
  ('barn',    'site_label',   '"Tuckaway Cooperative Riding Club"'),
  ('barn',    'farmos_host',  '"https://tuckaway.farmos.net"'),
  ('kennel',  'site_label',   '"Wentworth Hunt Kennels"'),
  ('kennel',  'farmos_host',  '""'),
  ('hunters', 'site_label',   '"Tuckaway Farm — Hunter Management"'),
  ('hunters', 'farmos_host',  '"https://tuckaway.farmos.net"'),
  ('all',     'farm_name',    '"Tuckaway Farm / Wentworth Hunt"'),
  ('all',     'farm_location','"Lee, New Hampshire"')
ON CONFLICT (site, key) DO NOTHING;

-- ============================================================================
-- HELPFUL VIEWS
-- ============================================================================

-- Members with document status
CREATE OR REPLACE VIEW member_doc_status AS
SELECT
  p.id,
  p.full_name,
  p.email,
  p.role,
  p.member_type,
  p.is_active,
  MAX(CASE WHEN d.doc_type = 'liability_release'  AND d.is_valid THEN d.signed_at END) AS liability_signed,
  MAX(CASE WHEN d.doc_type = 'boarding_agreement' AND d.is_valid THEN d.signed_at END) AS boarding_signed,
  MAX(CASE WHEN d.doc_type = 'hunter_release'     AND d.is_valid THEN d.signed_at END) AS hunter_signed,
  MAX(CASE WHEN d.doc_type = 'hunt_membership'    AND d.is_valid THEN d.signed_at END) AS membership_signed,
  COUNT(d.id) FILTER (WHERE d.is_valid) AS total_docs
FROM profiles p
LEFT JOIN documents d ON d.user_id = p.id
GROUP BY p.id;

-- ============================================================================
-- CREDENTIALS YOU NEED (see farmhack-admin.html for setup UI)
-- ============================================================================
--
--  1. Project URL   → Supabase Dashboard → Settings → API → Project URL
--                     e.g. https://abcdefghijklm.supabase.co
--
--  2. Anon Key      → Supabase Dashboard → Settings → API → Project API Keys → anon public
--                     e.g. eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
--                     ✓ SAFE to embed in browser HTML — RLS enforces access
--
--  3. Service Role Key (KEEP SECRET — server/admin use only)
--                     → Settings → API → service_role
--                     ✗ NEVER put in browser HTML
--                     ✓ Use in farmhack-admin.html for bulk user management
--
--  4. JWT Secret    → Settings → API → JWT Settings
--                     Only needed if you build a custom server middleware
--
-- ============================================================================
