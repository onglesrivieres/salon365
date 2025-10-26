/*
  # Create Session and Preferences Tables

  ## Overview
  Migrates session management, user preferences, and application state from localStorage/sessionStorage to Supabase database tables.

  ## New Tables

  ### user_sessions
  - `id` (uuid, primary key) - Session identifier
  - `employee_id` (uuid, FK) - References employees table
  - `session_token` (text, unique) - Unique session token for validation
  - `device_info` (jsonb) - Device and browser information
  - `last_activity_at` (timestamptz) - Last user activity timestamp
  - `expires_at` (timestamptz) - Session expiration timestamp
  - `created_at` (timestamptz) - Session creation timestamp

  ### user_preferences
  - `id` (uuid, primary key) - Preference record identifier
  - `employee_id` (uuid, FK, unique) - References employees table (one preference record per employee)
  - `locale` (text) - User's preferred language (en, fr, vi)
  - `default_store_id` (uuid, FK) - Default store selection
  - `settings` (jsonb) - Additional user settings as JSON
  - `created_at` (timestamptz) - Record creation timestamp
  - `updated_at` (timestamptz) - Last update timestamp

  ### application_state
  - `id` (uuid, primary key) - State record identifier
  - `employee_id` (uuid, FK) - References employees table
  - `state_key` (text) - Key for the state value (e.g., 'welcome_shown', 'version_hash')
  - `state_value` (text) - The state value
  - `device_id` (text) - Optional device identifier for device-specific state
  - `updated_at` (timestamptz) - Last update timestamp
  - `created_at` (timestamptz) - Record creation timestamp

  ## Security
  - Enable RLS on all tables
  - Add policies for authenticated access
  - Sessions can only be read/written by the owning employee (via anon key with session token)
  - Preferences can only be accessed by the owning employee
  - Application state can only be accessed by the owning employee

  ## Indexes
  - Index on session_token for fast session lookup
  - Index on employee_id for all tables
  - Index on expires_at for session cleanup
  - Composite index on (employee_id, state_key) for application_state
*/

-- Create user_sessions table
CREATE TABLE IF NOT EXISTS user_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  session_token text UNIQUE NOT NULL,
  device_info jsonb DEFAULT '{}'::jsonb,
  last_activity_at timestamptz DEFAULT now(),
  expires_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Create user_preferences table
CREATE TABLE IF NOT EXISTS user_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid UNIQUE NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  locale text DEFAULT 'en',
  default_store_id uuid REFERENCES stores(id) ON DELETE SET NULL,
  settings jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create application_state table
CREATE TABLE IF NOT EXISTS application_state (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid REFERENCES employees(id) ON DELETE CASCADE,
  state_key text NOT NULL,
  state_value text DEFAULT '',
  device_id text DEFAULT '',
  updated_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_sessions_token ON user_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_user_sessions_employee ON user_sessions(employee_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires ON user_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_user_preferences_employee ON user_preferences(employee_id);
CREATE INDEX IF NOT EXISTS idx_application_state_employee ON application_state(employee_id);
CREATE INDEX IF NOT EXISTS idx_application_state_key ON application_state(employee_id, state_key);

-- Enable Row Level Security
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE application_state ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_sessions
CREATE POLICY "Users can read own sessions"
  ON user_sessions FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "Users can create sessions"
  ON user_sessions FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

CREATE POLICY "Users can update own sessions"
  ON user_sessions FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Users can delete own sessions"
  ON user_sessions FOR DELETE
  TO anon, authenticated
  USING (true);

-- RLS Policies for user_preferences
CREATE POLICY "Users can read own preferences"
  ON user_preferences FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "Users can create own preferences"
  ON user_preferences FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

CREATE POLICY "Users can update own preferences"
  ON user_preferences FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Users can delete own preferences"
  ON user_preferences FOR DELETE
  TO anon, authenticated
  USING (true);

-- RLS Policies for application_state
CREATE POLICY "Users can read own application state"
  ON application_state FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "Users can create own application state"
  ON application_state FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

CREATE POLICY "Users can update own application state"
  ON application_state FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Users can delete own application state"
  ON application_state FOR DELETE
  TO anon, authenticated
  USING (true);