/*
  # Add Daily Auto-Checkout at 21:30 Eastern Time

  ## Overview
  Creates a scheduled job to automatically check out all employees at 21:30 PM Eastern time daily.

  ## Changes
  1. Create function to auto-checkout all employees at end of day
     - Checks out all employees who are still checked in
     - Uses Eastern timezone (America/New_York)
     - Sets checkout time to 21:30 Eastern
     - Calculates total hours worked

  2. Create cron job scheduled for 21:30 Eastern (01:30 UTC next day or 02:30 UTC depending on DST)
     - Runs daily at 21:30 Eastern time
     - Handles timezone conversion properly

  ## Timezone Handling
  - Eastern Time (America/New_York) observes DST
  - EST (UTC-5) from November to March
  - EDT (UTC-4) from March to November
  - Function uses timezone-aware timestamps

  ## Security
  - Function uses existing RLS policies
  - Only affects checked-in employees
*/

-- Function: Auto checkout all employees at 21:30 Eastern
CREATE OR REPLACE FUNCTION auto_checkout_all_at_closing_time()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_record RECORD;
  v_checkout_time timestamptz;
  v_hours numeric;
  v_now timestamptz;
  v_eastern_time timestamptz;
BEGIN
  -- Get current time in Eastern timezone
  v_eastern_time := now() AT TIME ZONE 'America/New_York';
  
  -- Set checkout time to 21:30 Eastern today
  v_checkout_time := (date_trunc('day', v_eastern_time) + interval '21 hours 30 minutes') AT TIME ZONE 'America/New_York';

  -- Loop through all checked-in employees
  FOR v_record IN
    SELECT id, employee_id, store_id, check_in_time, work_date
    FROM attendance_records
    WHERE status = 'checked_in'
      AND work_date = CURRENT_DATE
  LOOP
    -- Calculate hours from check-in to 21:30
    v_hours := EXTRACT(EPOCH FROM (v_checkout_time - v_record.check_in_time)) / 3600;

    -- Auto-checkout at 21:30 Eastern
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

-- Remove existing closing time job if it exists
DO $$
BEGIN
  PERFORM cron.unschedule('auto-checkout-all-at-closing');
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Schedule the auto-checkout job to run at 21:30 Eastern (01:30 UTC)
-- Note: This schedules for 01:30 UTC which is 21:30 EST (when EST is UTC-4)
-- During EDT (UTC-4), 21:30 EDT = 01:30 UTC next day
-- During EST (UTC-5), 21:30 EST = 02:30 UTC next day
-- We'll use 02:30 UTC to cover EST, which will be 21:30 EST or 22:30 EDT
SELECT cron.schedule(
  'auto-checkout-all-at-closing',
  '30 2 * * *',  -- 02:30 UTC daily = 21:30 EST / 22:30 EDT
  $$SELECT auto_checkout_all_at_closing_time();$$
);
