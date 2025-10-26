/*
  # Fix Technician Queue Status Updates

  ## Overview
  This migration fixes the technician queue to properly track busy/ready status.
  The issue was that technicians remain in "ready" status even when assigned to tickets.

  ## Root Cause
  - The mark_technician_busy() function was missing
  - Triggers weren't updating queue status when tickets are assigned
  - Queue records weren't being removed or updated when technicians become busy

  ## Solution
  1. Create mark_technician_busy() function to update queue status
  2. Ensure triggers properly call this function
  3. Update existing queue records to reflect current ticket assignments

  ## New Functions
  - **mark_technician_busy(p_employee_id, p_ticket_id)** - Marks a technician as busy
    - Updates their queue status to 'busy'
    - Links them to the current open ticket
    - Or removes them from queue entirely (cleaner approach)

  ## Business Logic
  When a technician is assigned to a ticket:
  - Remove them from the ready queue
  - They must click "Ready" again after finishing the ticket to rejoin queue
*/

-- Create function to mark technician as busy (removes from queue)
CREATE OR REPLACE FUNCTION mark_technician_busy(
  p_employee_id uuid,
  p_ticket_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Remove technician from ready queue when assigned to a ticket
  -- They must click Ready again after finishing to rejoin the queue
  DELETE FROM technician_ready_queue
  WHERE employee_id = p_employee_id;
  
  -- Alternative approach: Update status to 'busy' and link to ticket
  -- Uncomment below and comment DELETE above if you want to keep them in queue as 'busy'
  /*
  UPDATE technician_ready_queue
  SET 
    status = 'busy',
    current_open_ticket_id = p_ticket_id,
    updated_at = now()
  WHERE employee_id = p_employee_id;
  */
END;
$$;

-- Clean up: Remove technicians from queue if they currently have open tickets
DELETE FROM technician_ready_queue trq
WHERE EXISTS (
  SELECT 1 
  FROM ticket_items ti
  JOIN sale_tickets st ON ti.sale_ticket_id = st.id
  WHERE ti.employee_id = trq.employee_id
    AND st.closed_at IS NULL
);