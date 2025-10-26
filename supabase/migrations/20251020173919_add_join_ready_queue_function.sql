/*
  # Add Join Ready Queue Function

  ## Overview
  Creates a function to allow technicians to join the ready queue when they're
  available to take customers. This was missing after migration to Supabase.

  ## Function Purpose
  - Allows technicians to signal they're ready for customers
  - Sets their position in the queue based on timestamp
  - Prevents duplicate entries (removes old entry if exists)

  ## Usage
  Called when a technician clicks "I'm Ready" or "Join Queue" button
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