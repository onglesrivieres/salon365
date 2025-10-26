/*
  # Update Auto-Checkout Logic for Daily Employees

  ## Overview
  Updates the auto-checkout functionality to check out daily-paid employees 2 hours after their last completed service.

  ## Changes
  1. Update `auto_checkout_inactive_daily_employees` function
     - Change inactivity threshold from 3 hours to 2 hours
     - Check against last completed service time (ticket_items closed_at)
     - Auto-checkout using the last service completion time

  2. Add helper function to get last service completion time
     - Queries ticket_items for the most recent closed service by employee
     - Returns the closed_at timestamp

  ## Logic
  - For daily employees who are checked in
  - Find their last completed service (ticket closed_at time)
  - If no activity for 2+ hours since last service completion
  - Auto-checkout with last service completion as checkout time

  ## Security
  - Functions are secure and use existing RLS policies
*/

-- Function: Get last service completion time for an employee
CREATE OR REPLACE FUNCTION get_last_service_completion_time(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS timestamptz
LANGUAGE plpgsql
AS $$
DECLARE
  v_last_completion timestamptz;
BEGIN
  -- Get the most recent closed ticket for this employee at this store
  SELECT MAX(st.closed_at) INTO v_last_completion
  FROM ticket_items ti
  JOIN sale_tickets st ON ti.ticket_id = st.id
  WHERE ti.employee_id = p_employee_id
    AND st.store_id = p_store_id
    AND st.ticket_date = CURRENT_DATE
    AND st.closed_at IS NOT NULL;

  RETURN v_last_completion;
END;
$$;

-- Function: Auto checkout inactive daily employees (2+ hours since last service completion)
CREATE OR REPLACE FUNCTION auto_checkout_inactive_daily_employees()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_cutoff_time timestamptz := now() - interval '2 hours';
  v_hours numeric;
  v_record RECORD;
  v_last_service_time timestamptz;
BEGIN
  FOR v_record IN
    SELECT id, employee_id, store_id, check_in_time, last_activity_time
    FROM attendance_records
    WHERE status = 'checked_in'
      AND pay_type = 'daily'
      AND work_date = CURRENT_DATE
  LOOP
    -- Get the last service completion time for this employee
    v_last_service_time := get_last_service_completion_time(v_record.employee_id, v_record.store_id);

    -- If they have completed services and it's been 2+ hours since last completion
    IF v_last_service_time IS NOT NULL AND v_last_service_time < v_cutoff_time THEN
      -- Calculate hours from check-in to last service completion
      v_hours := EXTRACT(EPOCH FROM (v_last_service_time - v_record.check_in_time)) / 3600;

      -- Auto-checkout with last service completion time as checkout time
      UPDATE attendance_records
      SET
        check_out_time = v_last_service_time,
        status = 'auto_checked_out',
        total_hours = v_hours,
        updated_at = now()
      WHERE id = v_record.id;
    END IF;
  END LOOP;
END;
$$;
