/*
  # Fix Auto-Checkout Timezone Handling for Eastern Time

  ## Overview
  Fixes the auto-checkout scheduling to properly handle Eastern timezone (America/New_York)
  with automatic DST adjustments.

  ## Changes
  1. Update auto_checkout_all_at_closing_time function
     - Remove timezone conversion in function (cron handles this)
     - Use simple 21:30 local time for checkout
     
  2. Update cron schedule
     - Remove old job
     - Create two jobs: one for EST (02:30 UTC) and one for EDT (01:30 UTC)
     - OR use pg_cron timezone support if available

  ## Timezone Logic
  - EST (Winter): UTC-5, so 21:30 EST = 02:30 UTC next day
  - EDT (Summer): UTC-4, so 21:30 EDT = 01:30 UTC next day
  - We need the job to run at both times OR use timezone-aware scheduling

  ## Security
  - Function uses existing RLS policies
*/

-- Update function to use simpler checkout time logic
CREATE OR REPLACE FUNCTION auto_checkout_all_at_closing_time()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_record RECORD;
  v_checkout_time timestamptz;
  v_hours numeric;
  v_eastern_now time;
BEGIN
  -- Get current time in Eastern timezone (just the time part)
  v_eastern_now := (now() AT TIME ZONE 'America/New_York')::time;
  
  -- Only proceed if it's between 21:30 and 21:45 Eastern
  -- This prevents the job from running at wrong times
  IF v_eastern_now < '21:30:00'::time OR v_eastern_now > '21:45:00'::time THEN
    RETURN;
  END IF;

  -- Set checkout time to exactly 21:30 Eastern today
  v_checkout_time := (date_trunc('day', now() AT TIME ZONE 'America/New_York') + interval '21 hours 30 minutes') AT TIME ZONE 'America/New_York';

  -- Loop through all checked-in employees
  FOR v_record IN
    SELECT id, employee_id, store_id, check_in_time, work_date
    FROM attendance_records
    WHERE status = 'checked_in'
      AND work_date = CURRENT_DATE
  LOOP
    -- Calculate hours from check-in to 21:30
    v_hours := EXTRACT(EPOCH FROM (v_checkout_time - v_record.check_in_time)) / 3600;

    -- Ensure hours is not negative
    IF v_hours < 0 THEN
      v_hours := 0;
    END IF;

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

-- Remove old jobs
DO $$
BEGIN
  PERFORM cron.unschedule('auto-checkout-all-at-closing');
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-checkout-all-at-closing-est');
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-checkout-all-at-closing-edt');
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Schedule job to run at 01:30 UTC (21:30 EDT) and 02:30 UTC (21:30 EST)
-- Running both ensures we catch it regardless of DST
SELECT cron.schedule(
  'auto-checkout-all-at-closing-edt',
  '30 1 * * *',  -- 01:30 UTC = 21:30 EDT (summer)
  $$SELECT auto_checkout_all_at_closing_time();$$
);

SELECT cron.schedule(
  'auto-checkout-all-at-closing-est',
  '30 2 * * *',  -- 02:30 UTC = 21:30 EST (winter)
  $$SELECT auto_checkout_all_at_closing_time();$$
);
