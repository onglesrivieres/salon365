/*
  # Create Triggers for Automatic Queue Status Updates

  ## Overview
  Creates database triggers to automatically update technician queue status
  based on ticket assignment and closure events.

  ## Triggers

  1. **trigger_mark_technician_busy**
     - Fires when a new ticket_item is inserted
     - Automatically marks the assigned technician as busy
     - Links the technician to the open ticket

  2. **trigger_mark_technician_available**
     - Fires when a sale_ticket is closed (closed_at updated)
     - Automatically removes technicians from queue when their ticket is closed
     - Ensures technicians must click Ready again to rejoin queue

  ## Security
  - Triggers run with security definer privileges
  - Only affect records that meet specific criteria
*/

-- Trigger function: Mark technician as busy when assigned to a new ticket
CREATE OR REPLACE FUNCTION trigger_mark_technician_busy()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_ticket_closed_at timestamptz;
BEGIN
  -- Check if the ticket is still open
  SELECT closed_at INTO v_ticket_closed_at
  FROM sale_tickets
  WHERE id = NEW.sale_ticket_id;

  -- Only mark as busy if ticket is still open
  IF v_ticket_closed_at IS NULL THEN
    PERFORM mark_technician_busy(NEW.employee_id, NEW.sale_ticket_id);
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger function: Remove technicians from queue when ticket is closed
CREATE OR REPLACE FUNCTION trigger_mark_technicians_available()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only process if ticket was just closed (closed_at changed from NULL to a value)
  IF OLD.closed_at IS NULL AND NEW.closed_at IS NOT NULL THEN
    -- Remove all technicians who worked on this ticket from the queue
    DELETE FROM technician_ready_queue
    WHERE current_open_ticket_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- Create trigger on ticket_items for new assignments
DROP TRIGGER IF EXISTS ticket_items_mark_busy ON ticket_items;
CREATE TRIGGER ticket_items_mark_busy
  AFTER INSERT ON ticket_items
  FOR EACH ROW
  EXECUTE FUNCTION trigger_mark_technician_busy();

-- Create trigger on sale_tickets for ticket closure
DROP TRIGGER IF EXISTS sale_tickets_mark_available ON sale_tickets;
CREATE TRIGGER sale_tickets_mark_available
  AFTER UPDATE OF closed_at ON sale_tickets
  FOR EACH ROW
  EXECUTE FUNCTION trigger_mark_technicians_available();
