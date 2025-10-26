/*
  # Add Automatic Queue Release at Closing Time

  ## Overview
  Automatically removes all technicians from the ready queue at store closing times.
  Handles different closing times for different days of the week.

  ## Ongles Rivieres Operating Hours (Eastern Time)
  - Monday - Wednesday: 9:30 AM - 5:30 PM (17:30)
  - Thursday - Friday: 9:00 AM - 9:00 PM (21:00)
  - Saturday: 9:00 AM - 5:00 PM (17:00)
  - Sunday: 10:00 AM - 5:00 PM (17:00)

  ## Changes
  1. Create function to clear ready queue at closing time
     - Removes all technicians from queue regardless of store
     - Called by cron jobs at different closing times
     - Uses Eastern timezone

  2. Create multiple cron jobs for different closing times
     - 17:00 (5:00 PM) - Saturday & Sunday
     - 17:30 (5:30 PM) - Monday, Tuesday, Wednesday
     - 21:00 (9:00 PM) - Thursday & Friday

  ## Timezone Handling
  - All times are in Eastern (America/New_York)
  - Automatically handles DST transitions
  - Uses day-of-week checking to run at correct times

  ## Security
  - Function uses existing RLS policies
  - Only affects ready queue status
*/

-- Function: Auto release all technicians from queue at closing time
CREATE OR REPLACE FUNCTION auto_release_queue_at_closing()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_eastern_time timestamptz;
  v_eastern_time_only time;
  v_day_of_week integer;
BEGIN
  -- Get current time in Eastern timezone
  v_eastern_time := now() AT TIME ZONE 'America/New_York';
  v_eastern_time_only := v_eastern_time::time;
  
  -- Get day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
  v_day_of_week := EXTRACT(DOW FROM v_eastern_time);
  
  -- Check if we should clear the queue based on day and time
  -- Monday (1), Tuesday (2), Wednesday (3): Close at 17:30
  IF v_day_of_week IN (1, 2, 3) AND v_eastern_time_only >= '17:30:00'::time AND v_eastern_time_only < '17:45:00'::time THEN
    DELETE FROM technician_ready_queue;
    RETURN;
  END IF;
  
  -- Thursday (4), Friday (5): Close at 21:00
  IF v_day_of_week IN (4, 5) AND v_eastern_time_only >= '21:00:00'::time AND v_eastern_time_only < '21:15:00'::time THEN
    DELETE FROM technician_ready_queue;
    RETURN;
  END IF;
  
  -- Saturday (6): Close at 17:00
  IF v_day_of_week = 6 AND v_eastern_time_only >= '17:00:00'::time AND v_eastern_time_only < '17:15:00'::time THEN
    DELETE FROM technician_ready_queue;
    RETURN;
  END IF;
  
  -- Sunday (0): Close at 17:00
  IF v_day_of_week = 0 AND v_eastern_time_only >= '17:00:00'::time AND v_eastern_time_only < '17:15:00'::time THEN
    DELETE FROM technician_ready_queue;
    RETURN;
  END IF;
END;
$$;

-- Remove old queue release jobs if they exist
DO $$
BEGIN
  PERFORM cron.unschedule('auto-release-queue-1700-est');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-release-queue-1700-edt');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-release-queue-1730-est');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-release-queue-1730-edt');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-release-queue-2100-est');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('auto-release-queue-2100-edt');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

-- Schedule queue release at 17:00 Eastern (Sat & Sun)
-- EDT: 17:00 EDT = 21:00 UTC
-- EST: 17:00 EST = 22:00 UTC
SELECT cron.schedule(
  'auto-release-queue-1700-edt',
  '0 21 * * *',
  $$SELECT auto_release_queue_at_closing();$$
);

SELECT cron.schedule(
  'auto-release-queue-1700-est',
  '0 22 * * *',
  $$SELECT auto_release_queue_at_closing();$$
);

-- Schedule queue release at 17:30 Eastern (Mon-Wed)
-- EDT: 17:30 EDT = 21:30 UTC
-- EST: 17:30 EST = 22:30 UTC
SELECT cron.schedule(
  'auto-release-queue-1730-edt',
  '30 21 * * *',
  $$SELECT auto_release_queue_at_closing();$$
);

SELECT cron.schedule(
  'auto-release-queue-1730-est',
  '30 22 * * *',
  $$SELECT auto_release_queue_at_closing();$$
);

-- Schedule queue release at 21:00 Eastern (Thu-Fri)
-- EDT: 21:00 EDT = 01:00 UTC next day
-- EST: 21:00 EST = 02:00 UTC next day
SELECT cron.schedule(
  'auto-release-queue-2100-edt',
  '0 1 * * *',
  $$SELECT auto_release_queue_at_closing();$$
);

SELECT cron.schedule(
  'auto-release-queue-2100-est',
  '0 2 * * *',
  $$SELECT auto_release_queue_at_closing();$$
);
