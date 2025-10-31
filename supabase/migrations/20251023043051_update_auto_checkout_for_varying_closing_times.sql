/*
  # Update Auto-Checkout for Single Store System

  ## Overview
  Updates the employee auto-checkout function for the single store system
  (Sans Souci Ongles & Spa) with standardized closing times.

  ## Sans Souci Ongles & Spa Operating Hours (Eastern Time)
  - Standard closing time: 9:00 PM (21:00) for all days

  ## Changes
  1. Update auto_checkout_all_at_closing_time function
     - Use standard closing time for all days
     - Handle timezone properly

  2. Update cron schedules
     - Single schedule for consistent closing time
     - Job runs at standard closing time

  ## Security
  - Function uses existing RLS policies
*/

-- Function: Auto checkout all employees at store closing time
CREATE OR REPLACE FUNCTION auto_checkout_all_at_closing_time()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_record RECORD;
  v_checkout_time timestamptz;
  v_hours numeric;
  v_eastern_time timestamptz;
  v_eastern_time_only time;
BEGIN
  -- Get current time in Eastern timezone
  v_eastern_time := now() AT TIME ZONE 'America/New_York';
  v_eastern_time_only := v_eastern_time::time;
  
  -- Standard closing time: 9:00 PM (21:00) Eastern Time
  -- Only run if current time is between 21:00 and 21:15
  IF v_eastern_time_only < '21:00:00'::time OR v_eastern_time_only > '21:15:00'::time THEN
    RETURN;
  END IF;

  -- Set checkout time to 21:00 Eastern for today
  v_checkout_time := (date_trunc('day', v_eastern_time) + interval '21 hours')
                    AT TIME ZONE 'America/New_York';

  -- Loop through all checked-in employees
  FOR v_record IN
    SELECT id, employee_id, store_id, check_in_time, work_date
    FROM attendance_records
    WHERE status = 'checked_in'
      AND work_date = CURRENT_DATE
  LOOP
    -- Calculate hours from check-in to closing time
    v_hours := EXTRACT(EPOCH FROM (v_checkout_time - v_record.check_in_time)) / 3600;

    -- Ensure hours is not negative
    IF v_hours < 0 THEN
      v_hours := 0;
    END IF;

    -- Auto-checkout at closing time
    UPDATE attendance_records
    SET
      check_out_time = v_checkout_time,
      status = 'auto_checked_out',
      total_hours = v_hours,
      updated_at = now()
    WHERE id = v_record.id;
  END LOOP;
END;
$$;

-- Schedule checkout at 21:00 Eastern Time
-- EDT: 21:00 EDT = 01:00+1 UTC
-- EST: 21:00 EST = 02:00+1 UTC
SELECT cron.schedule(
  'auto-checkout-2100-edt',
  '0 1 * * *',
  $$SELECT auto_checkout_all_at_closing_time();$$
);

SELECT cron.schedule(
  'auto-checkout-2100-est',
  '0 2 * * *',
  $$SELECT auto_checkout_all_at_closing_time();$$
);
