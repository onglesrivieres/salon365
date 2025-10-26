/*
  # Create Attendance Records System

  ## Overview
  Creates an attendance tracking system for employees to manage check-in and check-out times.
  Supports both hourly employees (manual check-in/out) and daily employees (automatic tracking via Ready clicks).

  ## New Tables

  ### attendance_records
  - `id` (uuid, primary key) - Unique identifier
  - `employee_id` (uuid, foreign key) - References employees table
  - `store_id` (uuid, foreign key) - References stores table
  - `work_date` (date) - The date of work
  - `check_in_time` (timestamptz) - When employee checked in
  - `check_out_time` (timestamptz, nullable) - When employee checked out
  - `last_activity_time` (timestamptz, nullable) - Last Ready click for daily employees
  - `pay_type` (text) - Employee pay type at time of check-in (hourly/daily)
  - `status` (text) - Current status: 'checked_in', 'checked_out', 'auto_checked_out'
  - `total_hours` (numeric, nullable) - Calculated hours worked
  - `notes` (text) - Additional notes
  - `created_at` (timestamptz) - Record creation timestamp
  - `updated_at` (timestamptz) - Last update timestamp

  ## Indexes
  - employee_id, store_id, work_date for fast lookups
  - work_date for date range queries
  - status for filtering active records

  ## Security
  - Enable RLS on attendance_records table
  - Add policies for anonymous access (internal salon app)

  ## Functions
  - check_in_employee: Record employee check-in
  - check_out_employee: Record employee check-out
  - update_last_activity: Update last activity time for daily employees
  - auto_checkout_inactive_daily_employees: Auto checkout after 3 hours inactivity
  - get_employee_attendance_summary: Get attendance summary for date range
*/

-- Create attendance_records table
CREATE TABLE IF NOT EXISTS attendance_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  work_date date NOT NULL DEFAULT CURRENT_DATE,
  check_in_time timestamptz NOT NULL DEFAULT now(),
  check_out_time timestamptz,
  last_activity_time timestamptz,
  pay_type text NOT NULL CHECK (pay_type IN ('hourly', 'daily')),
  status text NOT NULL DEFAULT 'checked_in' CHECK (status IN ('checked_in', 'checked_out', 'auto_checked_out')),
  total_hours numeric(10,2),
  notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(employee_id, store_id, work_date)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_attendance_records_employee_id ON attendance_records(employee_id);
CREATE INDEX IF NOT EXISTS idx_attendance_records_store_id ON attendance_records(store_id);
CREATE INDEX IF NOT EXISTS idx_attendance_records_work_date ON attendance_records(work_date);
CREATE INDEX IF NOT EXISTS idx_attendance_records_status ON attendance_records(status);
CREATE INDEX IF NOT EXISTS idx_attendance_records_employee_date ON attendance_records(employee_id, work_date);

-- Enable Row Level Security
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;

-- Create policy for anonymous access (internal salon app)
CREATE POLICY "Allow all access to attendance_records"
  ON attendance_records FOR ALL
  USING (true)
  WITH CHECK (true);

-- Function: Check in employee
CREATE OR REPLACE FUNCTION check_in_employee(
  p_employee_id uuid,
  p_store_id uuid,
  p_pay_type text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_record_id uuid;
  v_work_date date := CURRENT_DATE;
BEGIN
  -- Check if already checked in today
  SELECT id INTO v_record_id
  FROM attendance_records
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id
    AND work_date = v_work_date
    AND status = 'checked_in';

  IF v_record_id IS NOT NULL THEN
    RETURN v_record_id;
  END IF;

  -- Create new attendance record
  INSERT INTO attendance_records (
    employee_id,
    store_id,
    work_date,
    check_in_time,
    last_activity_time,
    pay_type,
    status
  ) VALUES (
    p_employee_id,
    p_store_id,
    v_work_date,
    now(),
    now(),
    p_pay_type,
    'checked_in'
  )
  ON CONFLICT (employee_id, store_id, work_date)
  DO UPDATE SET
    check_in_time = now(),
    last_activity_time = now(),
    status = 'checked_in',
    check_out_time = NULL,
    total_hours = NULL,
    updated_at = now()
  RETURNING id INTO v_record_id;

  RETURN v_record_id;
END;
$$;

-- Function: Check out employee
CREATE OR REPLACE FUNCTION check_out_employee(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_check_in_time timestamptz;
  v_hours numeric;
BEGIN
  -- Get check-in time
  SELECT check_in_time INTO v_check_in_time
  FROM attendance_records
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id
    AND work_date = CURRENT_DATE
    AND status = 'checked_in';

  IF v_check_in_time IS NULL THEN
    RETURN false;
  END IF;

  -- Calculate hours worked
  v_hours := EXTRACT(EPOCH FROM (now() - v_check_in_time)) / 3600;

  -- Update attendance record
  UPDATE attendance_records
  SET
    check_out_time = now(),
    status = 'checked_out',
    total_hours = v_hours,
    updated_at = now()
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id
    AND work_date = CURRENT_DATE
    AND status = 'checked_in';

  RETURN true;
END;
$$;

-- Function: Update last activity time for daily employees
CREATE OR REPLACE FUNCTION update_last_activity(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE attendance_records
  SET
    last_activity_time = now(),
    updated_at = now()
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id
    AND work_date = CURRENT_DATE
    AND status = 'checked_in'
    AND pay_type = 'daily';
END;
$$;

-- Function: Auto checkout inactive daily employees (3+ hours since last activity)
CREATE OR REPLACE FUNCTION auto_checkout_inactive_daily_employees()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_cutoff_time timestamptz := now() - interval '3 hours';
  v_hours numeric;
  v_record RECORD;
BEGIN
  FOR v_record IN
    SELECT id, employee_id, check_in_time, last_activity_time
    FROM attendance_records
    WHERE status = 'checked_in'
      AND pay_type = 'daily'
      AND last_activity_time IS NOT NULL
      AND last_activity_time < v_cutoff_time
  LOOP
    -- Use last_activity_time as checkout time for daily employees
    v_hours := EXTRACT(EPOCH FROM (v_record.last_activity_time - v_record.check_in_time)) / 3600;

    UPDATE attendance_records
    SET
      check_out_time = v_record.last_activity_time,
      status = 'auto_checked_out',
      total_hours = v_hours,
      updated_at = now()
    WHERE id = v_record.id;
  END LOOP;
END;
$$;

-- Function: Get employee attendance summary
CREATE OR REPLACE FUNCTION get_employee_attendance_summary(
  p_employee_id uuid,
  p_start_date date,
  p_end_date date
)
RETURNS TABLE (
  work_date date,
  check_in_time timestamptz,
  check_out_time timestamptz,
  total_hours numeric,
  status text,
  store_name text
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ar.work_date,
    ar.check_in_time,
    ar.check_out_time,
    ar.total_hours,
    ar.status,
    s.name as store_name
  FROM attendance_records ar
  JOIN stores s ON ar.store_id = s.id
  WHERE ar.employee_id = p_employee_id
    AND ar.work_date BETWEEN p_start_date AND p_end_date
  ORDER BY ar.work_date DESC, ar.check_in_time DESC;
END;
$$;

-- Function: Get store attendance for date range
CREATE OR REPLACE FUNCTION get_store_attendance(
  p_store_id uuid,
  p_start_date date,
  p_end_date date
)
RETURNS TABLE (
  employee_id uuid,
  employee_name text,
  work_date date,
  check_in_time timestamptz,
  check_out_time timestamptz,
  total_hours numeric,
  status text,
  pay_type text
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ar.employee_id,
    e.display_name as employee_name,
    ar.work_date,
    ar.check_in_time,
    ar.check_out_time,
    ar.total_hours,
    ar.status,
    ar.pay_type
  FROM attendance_records ar
  JOIN employees e ON ar.employee_id = e.id
  WHERE ar.store_id = p_store_id
    AND ar.work_date BETWEEN p_start_date AND p_end_date
  ORDER BY ar.work_date DESC, e.display_name ASC;
END;
$$;