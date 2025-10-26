/*
  # Create Auto-Checkout Cron Job

  ## Overview
  Creates a scheduled cron job that runs every 15 minutes to automatically check out
  daily-paid employees who have been inactive for 2+ hours after their last service completion.

  ## Changes
  1. Enable pg_cron extension (if not already enabled)
  2. Create cron job to run auto_checkout_inactive_daily_employees every 15 minutes
  3. Job runs at :00, :15, :30, :45 of every hour

  ## Schedule
  - Runs: Every 15 minutes
  - Function: auto_checkout_inactive_daily_employees()
  - Purpose: Automatically check out inactive daily employees

  ## Notes
  - The cron job uses pg_cron extension
  - If the extension is not available, the function can still be called manually
  - The job name is unique and can be updated/deleted if needed
*/

-- Enable pg_cron extension (may require superuser privileges)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Remove existing job if it exists (to allow re-running this migration)
DO $$
BEGIN
  -- Try to unschedule the job if it exists
  PERFORM cron.unschedule('auto-checkout-daily-employees');
EXCEPTION
  WHEN OTHERS THEN
    -- Job doesn't exist, continue
    NULL;
END $$;

-- Schedule the auto-checkout job to run every 15 minutes
SELECT cron.schedule(
  'auto-checkout-daily-employees',
  '*/15 * * * *',  -- Every 15 minutes
  $$SELECT auto_checkout_inactive_daily_employees();$$
);
