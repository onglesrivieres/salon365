/*
  # Create get_store_attendance Function

  ## Overview
  Creates the get_store_attendance function that returns attendance records
  for a store within a date range.

  ## New Function
  - get_store_attendance(p_store_id, p_start_date, p_end_date)
    - Returns attendance records with employee details
    - Includes attendance_record_id for comment association
    - Filters by store and date range
    - Orders by work_date DESC, employee name ASC

  ## Returns
  - attendance_record_id: UUID of the attendance record
  - employee_id: UUID of the employee
  - employee_name: Display name of the employee
  - work_date: Date of the attendance
  - check_in_time: Timestamp when employee checked in
  - check_out_time: Timestamp when employee checked out (nullable)
  - total_hours: Total hours worked
  - status: Attendance status (present, absent, etc.)
  - pay_type: Employee pay type (hourly, salary, commission)

  ## Security
  - Function is accessible to all users (internal salon app)
  - Uses existing RLS policies on underlying tables
*/

-- Drop old function if it exists (with old signature)
DROP FUNCTION IF EXISTS get_store_attendance(uuid, date);
DROP FUNCTION IF EXISTS get_store_attendance(uuid, date, date);

-- Create the function with correct signature
CREATE OR REPLACE FUNCTION get_store_attendance(
  p_store_id uuid,
  p_start_date date,
  p_end_date date
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
STABLE
SET search_path = public, pg_temp
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
  ORDER BY ar.work_date DESC, e.display_name ASC;
END;
$$;
