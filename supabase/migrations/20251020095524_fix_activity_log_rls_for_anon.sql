/*
  # Fix Activity Log RLS for Anonymous Users

  1. Changes
    - Drop existing policies that require authenticated users
    - Create new policies that allow anonymous users to read and insert activity logs
    - This is needed because the app uses PIN authentication, not Supabase Auth

  2. Security
    - Allow anonymous users to read all activity logs
    - Allow anonymous users to insert activity logs
    - Note: The app validates user sessions at the application layer via PIN authentication
*/

-- Drop existing policies
DROP POLICY IF EXISTS "Authenticated users can read activity logs" ON ticket_activity_log;
DROP POLICY IF EXISTS "Authenticated users can insert activity logs" ON ticket_activity_log;

-- Create new policies for anonymous access
CREATE POLICY "Allow anonymous to read activity logs"
  ON ticket_activity_log
  FOR SELECT
  TO anon
  USING (true);

CREATE POLICY "Allow anonymous to insert activity logs"
  ON ticket_activity_log
  FOR INSERT
  TO anon
  WITH CHECK (true);