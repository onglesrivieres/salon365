/*
  # Update Attendance Function for Spa Expert Role

  1. Changes
    - Update `get_store_attendance` to include Spa Expert role
    - Spa Experts can check in/out and track attendance like Technicians

  2. Purpose
    - Allow Spa Experts to appear in attendance reports
    - Ensure they can track their working hours
*/

CREATE OR REPLACE FUNCTION get_store_attendance(
  p_store_id uuid,
  p_start_date date,
  p_end_date date,
  p_employee_id uuid DEFAULT NULL
)
RETURNS TABLE(
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
    AND (p_employee_id IS NULL OR ar.employee_id = p_employee_id)
    AND e.role && ARRAY['Technician', 'Receptionist', 'Supervisor', 'Spa Expert']::text[]
  ORDER BY ar.work_date DESC, e.display_name ASC;
END;
$$;
