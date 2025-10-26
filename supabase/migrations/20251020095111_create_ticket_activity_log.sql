/*
  # Create Ticket Activity Log

  1. New Tables
    - `ticket_activity_log`
      - `id` (uuid, primary key)
      - `ticket_id` (uuid, foreign key to sale_tickets)
      - `employee_id` (uuid, foreign key to employees)
      - `action` (text) - Type of action: 'created', 'updated', 'closed', 'reopened'
      - `description` (text) - Human-readable description of the action
      - `changes` (jsonb) - JSON object with details of what changed
      - `created_at` (timestamptz)

  2. Security
    - Enable RLS on `ticket_activity_log` table
    - Add policy for authenticated users to read activity logs
    - Add policy for authenticated users to insert activity logs

  3. Indexes
    - Add index on ticket_id for fast lookups
    - Add index on created_at for sorting
*/

-- Create ticket_activity_log table
CREATE TABLE IF NOT EXISTS ticket_activity_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES sale_tickets(id) ON DELETE CASCADE,
  employee_id uuid REFERENCES employees(id),
  action text NOT NULL CHECK (action IN ('created', 'updated', 'closed', 'reopened')),
  description text NOT NULL,
  changes jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE ticket_activity_log ENABLE ROW LEVEL SECURITY;

-- Policy for reading activity logs (authenticated users can read all logs)
CREATE POLICY "Authenticated users can read activity logs"
  ON ticket_activity_log
  FOR SELECT
  TO authenticated
  USING (true);

-- Policy for inserting activity logs (authenticated users can insert logs)
CREATE POLICY "Authenticated users can insert activity logs"
  ON ticket_activity_log
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS ticket_activity_log_ticket_id_idx ON ticket_activity_log(ticket_id);
CREATE INDEX IF NOT EXISTS ticket_activity_log_created_at_idx ON ticket_activity_log(created_at DESC);