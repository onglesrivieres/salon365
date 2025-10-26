/*
  # Update Auto-Checkout for Varying Closing Times

  ## Overview
  Updates the employee auto-checkout function to respect Ongles Rivieres' varying closing times
  based on the day of the week.

  ## Ongles Rivieres Operating Hours (Eastern Time)
  - Monday - Wednesday: 9:30 AM - 5:30 PM (17:30)
  - Thursday - Friday: 9:00 AM - 9:00 PM (21:00)
  - Saturday: 9:00 AM - 5:00 PM (17:00)
  - Sunday: 10:00 AM - 5:00 PM (17:00)

  ## Changes
  1. Update auto_checkout_all_at_closing_time function
     - Determine closing time based on day of week
     - Use appropriate closing time for checkout
     - Handle timezone properly

  2. Update cron schedules
     - Keep multiple schedules to cover all closing times
     - Jobs run at different times based on store hours

  ## Security
  - Function uses existing RLS policies
*/

-- Function: Auto checkout all employees at store closing time (varies by day)
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
  v_day_of_week integer;
  v_closing_hour integer;
  v_closing_minute integer;
BEGIN
  -- Get current time in Eastern timezone
  v_eastern_time := now() AT TIME ZONE 'America/New_York';
  v_eastern_time_only := v_eastern_time::time;
  
  -- Get day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
  v_day_of_week := EXTRACT(DOW FROM v_eastern_time);
  
  -- Determine closing time based on day of week
  -- Monday (1), Tuesday (2), Wednesday (3): Close at 17:30
  IF v_day_of_week IN (1, 2, 3) THEN
    v_closing_hour := 17;
    v_closing_minute := 30;
    -- Only run if current time is between 17:30 and 17:45
    IF v_eastern_time_only < '17:30:00'::time OR v_eastern_time_only > '17:45:00'::time THEN
      RETURN;
    END IF;
  
  -- Thursday (4), Friday (5): Close at 21:00
  ELSIF v_day_of_week IN (4, 5) THEN
    v_closing_hour := 21;
    v_closing_minute := 0;
    -- Only run if current time is between 21:00 and 21:15
    IF v_eastern_time_only < '21:00:00'::time OR v_eastern_time_only > '21:15:00'::time THEN
      RETURN;
    END IF;
  
  -- Saturday (6): Close at 17:00
  ELSIF v_day_of_week = 6 THEN
    v_closing_hour := 17;
    v_closing_minute := 0;
    -- Only run if current time is between 17:00 and 17:15
    IF v_eastern_time_only < '17:00:00'::time OR v_eastern_time_only > '17:15:00'::time THEN
      RETURN;
    END IF;
  
  -- Sunday (0): Close at 17:00
  ELSIF v_day_of_week = 0 THEN
    v_closing_hour := 17;
    v_closing_minute := 0;
    -- Only run if current time is between 17:00 and 17:15
    IF v_eastern_time_only < '17:00:00'::time OR v_eastern_time_only > '17:15:00'::time THEN
      RETURN;
    END IF;
  
  ELSE
    -- Should not happen, but return if it does
    RETURN;
  END IF;

  -- Set checkout time to the closing time for today
  v_checkout_time := (date_trunc('day', v_eastern_time) + 
                      make_interval(hours => v_closing_hour, mins => v_closing_minute)) 
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

-- The existing cron jobs at 01:30 UTC and 02:30 UTC will handle 21:00 closing (Thu-Fri)
-- We need to add jobs for 17:00 and 17:30 closings

-- Remove old checkout jobs if they exist
DO $$
BEGIN
  PERFORM cron.unschedule('auto-checkout-1700-est');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-checkout-1700-edt');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-checkout-1730-est');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-checkout-1730-edt');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

-- Schedule checkout at 17:00 Eastern (Sat & Sun)
-- EDT: 17:00 EDT = 21:00 UTC
-- EST: 17:00 EST = 22:00 UTC
SELECT cron.schedule(
  'auto-checkout-1700-edt',
  '0 21 * * *',
  $$SELECT auto_checkout_all_at_closing_time();$$
);

SELECT cron.schedule(
  'auto-checkout-1700-est',
  '0 22 * * *',
  $$SELECT auto_checkout_all_at_closing_time();$$
);

-- Schedule checkout at 17:30 Eastern (Mon-Wed)
-- EDT: 17:30 EDT = 21:30 UTC
-- EST: 17:30 EST = 22:30 UTC
SELECT cron.schedule(
  'auto-checkout-1730-edt',
  '30 21 * * *',
  $$SELECT auto_checkout_all_at_closing_time();$$
);

SELECT cron.schedule(
  'auto-checkout-1730-est',
  '30 22 * * *',
  $$SELECT auto_checkout_all_at_closing_time();$$
);

-- The 21:00 closing jobs (Thu-Fri) already exist from previous migration
-- (auto-checkout-all-at-closing-edt and auto-checkout-all-at-closing-est)
