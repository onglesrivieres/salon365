/*
  # Update get_store_attendance function to include record ID

  Drops and recreates the get_store_attendance function to include the attendance_record_id
  so that comments can be associated with specific attendance records.
*/

DROP FUNCTION IF EXISTS get_store_attendance(uuid, date, date);

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
