/*
  # Create Attendance Comments Table

  1. New Tables
    - `attendance_comments`
      - `id` (uuid, primary key)
      - `attendance_record_id` (uuid, foreign key to attendance_records)
      - `employee_id` (uuid, foreign key to employees) - who made the comment
      - `comment` (text) - the comment text
      - `created_at` (timestamp)
      - `updated_at` (timestamp)

  2. Security
    - Enable RLS on `attendance_comments` table
    - Add policies for authenticated users to:
      - View all comments in their store
      - Create comments on attendance records in their store
      - Update/delete their own comments

  3. Indexes
    - Index on attendance_record_id for fast lookups
    - Index on employee_id for filtering by commenter
*/

-- Create attendance_comments table
CREATE TABLE IF NOT EXISTS attendance_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_record_id uuid NOT NULL REFERENCES attendance_records(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  comment text NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_attendance_comments_record_id ON attendance_comments(attendance_record_id);
CREATE INDEX IF NOT EXISTS idx_attendance_comments_employee_id ON attendance_comments(employee_id);

-- Enable RLS
ALTER TABLE attendance_comments ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view comments for attendance records in their store
CREATE POLICY "Users can view comments in their store"
  ON attendance_comments
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM attendance_records ar
      JOIN employee_stores es ON es.employee_id = auth.uid()
      WHERE ar.id = attendance_comments.attendance_record_id
      AND ar.store_id = es.store_id
    )
  );

-- Policy: Users can create comments on attendance records in their store
CREATE POLICY "Users can create comments in their store"
  ON attendance_comments
  FOR INSERT
  TO authenticated
  WITH CHECK (
    employee_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM attendance_records ar
      JOIN employee_stores es ON es.employee_id = auth.uid()
      WHERE ar.id = attendance_record_id
      AND ar.store_id = es.store_id
    )
  );

-- Policy: Users can update their own comments
CREATE POLICY "Users can update own comments"
  ON attendance_comments
  FOR UPDATE
  TO authenticated
  USING (employee_id = auth.uid())
  WITH CHECK (employee_id = auth.uid());

-- Policy: Users can delete their own comments
CREATE POLICY "Users can delete own comments"
  ON attendance_comments
  FOR DELETE
  TO authenticated
  USING (employee_id = auth.uid());
