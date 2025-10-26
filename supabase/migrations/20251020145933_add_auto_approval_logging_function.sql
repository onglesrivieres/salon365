/*
  # Add Auto-Approval Activity Logging Function

  ## Overview
  Creates a function to log auto-approval events to the ticket activity log.
  This is called by the auto-approve-tickets Edge Function after tickets
  are automatically approved.

  ## Function
  - **log_auto_approval_activity()** - Logs auto-approval events for recently approved tickets
    - Finds tickets that were auto-approved in the last 5 minutes
    - Creates activity log entries with approval details
    - Uses NULL employee_id since this is a system action

  ## Security
  - Function can be called by service role (Edge Function)
  - Creates audit trail for all auto-approvals
*/

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
      AND approved_at >= now() - INTERVAL '5 minutes'
      AND approved_at IS NOT NULL
  LOOP
    -- Check if activity log entry already exists to avoid duplicates
    IF NOT EXISTS (
      SELECT 1 FROM ticket_activity_log
      WHERE ticket_id = v_ticket.id
        AND action = 'approved'
        AND description LIKE '%automatically approved%'
    ) THEN
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
        'Ticket automatically approved after 48-hour deadline',
        json_build_object(
          'approval_type', 'auto_approved',
          'ticket_no', v_ticket.ticket_no,
          'customer_name', v_ticket.customer_name,
          'total', v_ticket.total
        )
      );
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql;