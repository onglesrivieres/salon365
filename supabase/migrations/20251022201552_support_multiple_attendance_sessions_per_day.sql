/*
  # Support Multiple Attendance Sessions Per Day

  ## Overview
  Allows hourly employees to check in and out multiple times in a single day,
  showing all shift sessions in the attendance page.

  ## Changes

  ### 1. Database Schema
  - Remove UNIQUE constraint on (employee_id, store_id, work_date)
  - This allows multiple attendance records per employee per day
  - Each check-in/out session becomes a separate record

  ### 2. Updated Functions
  - `check_in_employee`: Remove ON CONFLICT clause, always create new record
  - `check_out_employee`: Check out the most recent checked_in record
  - `get_store_attendance`: Add attendance_record_id and order by check_in_time

  ## Impact
  - Hourly employees can have multiple sessions per day
  - Each session tracked separately with its own check-in/out times
  - Total hours calculated per session
  - UI will display all sessions for transparency

  ## Security
  - RLS policies remain unchanged (allow all access)
  - No data loss - existing records preserved
*/

-- Drop the unique constraint
ALTER TABLE attendance_records DROP CONSTRAINT IF EXISTS attendance_records_employee_id_store_id_work_date_key;

-- Drop existing functions to recreate them
DROP FUNCTION IF EXISTS check_in_employee(uuid, uuid, text);
DROP FUNCTION IF EXISTS check_out_employee(uuid, uuid);
DROP FUNCTION IF EXISTS get_store_attendance(uuid, date, date);
DROP FUNCTION IF EXISTS get_store_attendance(uuid, date, date, uuid);

-- Update check_in_employee function to always create new record
CREATE FUNCTION check_in_employee(
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
  -- Check if already checked in (no checkout yet)
  SELECT id INTO v_record_id
  FROM attendance_records
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id
    AND work_date = v_work_date
    AND status = 'checked_in'
    AND check_out_time IS NULL
  ORDER BY check_in_time DESC
  LIMIT 1;

  IF v_record_id IS NOT NULL THEN
    RETURN v_record_id;
  END IF;

  -- Create new attendance record (new session)
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
  RETURNING id INTO v_record_id;

  RETURN v_record_id;
END;
$$;

-- Update check_out_employee to check out the most recent active session
CREATE FUNCTION check_out_employee(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_check_in_time timestamptz;
  v_hours numeric;
  v_record_id uuid;
BEGIN
  -- Get the most recent checked-in record without checkout
  SELECT id, check_in_time 
  INTO v_record_id, v_check_in_time
  FROM attendance_records
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id
    AND work_date = CURRENT_DATE
    AND status = 'checked_in'
    AND check_out_time IS NULL
  ORDER BY check_in_time DESC
  LIMIT 1;

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
  WHERE id = v_record_id;

  RETURN true;
END;
$$;

-- Update get_store_attendance to include record ID and support filtering by employee
CREATE FUNCTION get_store_attendance(
  p_store_id uuid,
  p_start_date date,
  p_end_date date,
  p_employee_id uuid DEFAULT NULL
)
RETURNS TABLE (
  attendance_record_id uuid,
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
    ar.id as attendance_record_id,
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
    AND (p_employee_id IS NULL OR ar.employee_id = p_employee_id)
  ORDER BY ar.work_date DESC, ar.check_in_time ASC;
END;
$$;
