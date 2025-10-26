/*
  # Create Queue Management Triggers

  ## Overview
  Creates database triggers to automatically manage technician queue status
  based on ticket assignments and closures.

  ## Triggers Created

  1. **ticket_items_mark_busy**
     - Fires when a ticket_item is inserted (technician assigned to ticket)
     - Removes the technician from the ready queue
     - They must click "Ready" again after finishing to rejoin queue

  2. **sale_tickets_mark_available**
     - Fires when a sale_ticket is closed
     - Removes all technicians who worked on that ticket from the queue
     - They must explicitly click "Ready" to indicate availability

  ## Business Logic
  - Technicians are removed from queue when assigned to any ticket
  - Technicians are removed from queue when tickets close
  - Technicians must manually rejoin queue by clicking "Ready" button
  - This ensures the queue only shows truly available technicians

  ## Security
  - Triggers run automatically on data changes
  - Uses existing RLS policies
*/

-- Trigger function: Remove technician from queue when assigned to a ticket
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

  -- Only remove from queue if ticket is still open
  IF v_ticket_closed_at IS NULL THEN
    PERFORM mark_technician_busy(NEW.employee_id, NEW.sale_ticket_id);
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger function: Remove technicians from queue when their ticket is closed
CREATE OR REPLACE FUNCTION trigger_mark_technicians_available()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only process if ticket was just closed (closed_at changed from NULL to a value)
  IF OLD.closed_at IS NULL AND NEW.closed_at IS NOT NULL THEN
    -- Remove all technicians who worked on this ticket from the queue
    -- They must click "Ready" again to rejoin
    DELETE FROM technician_ready_queue
    WHERE employee_id IN (
      SELECT employee_id 
      FROM ticket_items 
      WHERE sale_ticket_id = NEW.id
    );
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