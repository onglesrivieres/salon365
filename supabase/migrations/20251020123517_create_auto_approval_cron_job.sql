/*
  # Create Auto-Approval Scheduled Job

  ## Overview
  This migration sets up a periodic job that automatically approves tickets
  when their 48-hour approval deadline has passed.

  ## Implementation
  - Uses pg_cron extension to schedule the auto-approval function
  - Runs every 15 minutes to check for expired approval deadlines
  - Updates ticket_activity_log to record auto-approval events

  ## Scheduled Job Details
  - Job name: auto_approve_expired_tickets
  - Schedule: Every 15 minutes
  - Function: auto_approve_expired_tickets()
*/

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Create function to log auto-approval activity
CREATE OR REPLACE FUNCTION log_auto_approval_activity()
RETURNS void AS $$
DECLARE
  v_ticket RECORD;
BEGIN
  -- Log auto-approval for tickets that were just auto-approved
  FOR v_ticket IN 
    SELECT id, ticket_no, customer_name, total
    FROM sale_tickets
    WHERE approval_status = 'auto_approved'
      AND approved_at >= now() - INTERVAL '1 minute'
  LOOP
    INSERT INTO ticket_activity_log (
      ticket_id,
      employee_id,
      action,
      description,
      changes
    ) VALUES (
      v_ticket.id,
      NULL,
      'approved',
      format('Ticket automatically approved after 48-hour deadline'),
      json_build_object(
        'approval_type', 'auto_approved',
        'ticket_no', v_ticket.ticket_no,
        'customer_name', v_ticket.customer_name,
        'total', v_ticket.total
      )
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create combined function that auto-approves and logs
CREATE OR REPLACE FUNCTION auto_approve_and_log()
RETURNS void AS $$
DECLARE
  v_result json;
BEGIN
  -- Run auto-approval
  SELECT auto_approve_expired_tickets() INTO v_result;
  
  -- Log the activity
  PERFORM log_auto_approval_activity();
END;
$$ LANGUAGE plpgsql;

-- Schedule the auto-approval job to run every 15 minutes
-- Note: pg_cron may require superuser privileges or specific setup in Supabase
-- If pg_cron is not available, this can be handled via a Supabase Edge Function with cron trigger
DO $$
BEGIN
  -- Try to schedule with pg_cron if available
  BEGIN
    PERFORM cron.schedule(
      'auto_approve_expired_tickets',
      '*/15 * * * *',
      'SELECT auto_approve_and_log()'
    );
  EXCEPTION
    WHEN OTHERS THEN
      -- If pg_cron scheduling fails, the function can still be called manually
      -- or via an Edge Function with cron trigger
      RAISE NOTICE 'pg_cron scheduling not available. Use Edge Function or manual execution.';
  END;
END $$;

-- Create a manual trigger alternative (can be called from Edge Function)
-- This allows running auto-approval on-demand or via Supabase Edge Functions
COMMENT ON FUNCTION auto_approve_and_log IS 
  'Automatically approves tickets past their 48-hour deadline and logs the activity. Can be called manually or via scheduled Edge Function if pg_cron is not available.';