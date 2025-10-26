/*
  # Create App Versions Table

  1. New Tables
    - `app_versions`
      - `id` (uuid, primary key) - Unique identifier for each version
      - `version_number` (text) - Semantic version number (e.g., "1.2.3")
      - `build_hash` (text) - Hash of the build for verification
      - `deployed_at` (timestamptz) - When this version was deployed
      - `release_notes` (text, nullable) - Optional release notes
      - `is_active` (boolean) - Whether this is the current active version
      - `created_at` (timestamptz) - Record creation timestamp
      - `updated_at` (timestamptz) - Record update timestamp

  2. Security
    - Enable RLS on `app_versions` table
    - Add policy for public read access (all users can check for updates)
    - Add policy for authenticated admin users to manage versions

  3. Indexes
    - Index on `is_active` for fast active version lookup
    - Index on `deployed_at` for version history queries

  4. Functions
    - Create function to get the latest active version
*/

CREATE TABLE IF NOT EXISTS app_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_number text NOT NULL,
  build_hash text NOT NULL,
  deployed_at timestamptz DEFAULT now(),
  release_notes text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE app_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active versions"
  ON app_versions
  FOR SELECT
  USING (is_active = true);

CREATE POLICY "Admins can manage versions"
  ON app_versions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = auth.uid()
      AND 'Admin' = ANY(employees.role)
    )
  );

CREATE INDEX IF NOT EXISTS idx_app_versions_is_active ON app_versions(is_active);
CREATE INDEX IF NOT EXISTS idx_app_versions_deployed_at ON app_versions(deployed_at DESC);

CREATE OR REPLACE FUNCTION get_latest_app_version()
RETURNS TABLE (
  id uuid,
  version_number text,
  build_hash text,
  deployed_at timestamptz,
  release_notes text
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    v.id,
    v.version_number,
    v.build_hash,
    v.deployed_at,
    v.release_notes
  FROM app_versions v
  WHERE v.is_active = true
  ORDER BY v.deployed_at DESC
  LIMIT 1;
END;
$$;
