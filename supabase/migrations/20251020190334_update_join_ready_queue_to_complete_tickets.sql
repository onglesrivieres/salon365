/*
  # Update Join Ready Queue Function to Complete Tickets

  ## Changes
  Updates the `join_ready_queue` function to mark any open tickets as completed
  before adding the technician to the ready queue.

  ## What it Does
  1. Finds all open tickets assigned to the technician in the store
  2. Marks those tickets as completed (sets completed_at and completed_by)
  3. Removes any existing queue entry for the technician
  4. Adds the technician to the ready queue

  ## Security
  - Only affects tickets assigned to the calling technician
  - Only affects tickets that are not already completed or closed
*/

CREATE OR REPLACE FUNCTION join_ready_queue(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Mark any open tickets assigned to this technician as completed
  UPDATE sale_tickets
  SET
    completed_at = NOW(),
    completed_by = p_employee_id,
    updated_at = NOW()
  WHERE id IN (
    SELECT DISTINCT ti.sale_ticket_id
    FROM ticket_items ti
    INNER JOIN sale_tickets st ON st.id = ti.sale_ticket_id
    WHERE ti.employee_id = p_employee_id
      AND st.store_id = p_store_id
      AND st.closed_at IS NULL
      AND st.completed_at IS NULL
  );

  -- Remove any existing entry for this technician in this store
  DELETE FROM technician_ready_queue
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id;

  -- Add technician to ready queue
  INSERT INTO technician_ready_queue (
    employee_id,
    store_id,
    status,
    ready_at
  ) VALUES (
    p_employee_id,
    p_store_id,
    'ready',
    NOW()
  );
END;
$$;