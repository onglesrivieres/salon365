/*
  # Add Queue Check and Leave Functions

  ## Overview
  Creates functions to check if an employee is in the ready queue and to leave the queue.

  ## New Functions
  
  ### check_queue_status
  - Takes employee_id and store_id as parameters
  - Returns boolean indicating if employee is in the ready queue
  - Used to determine if user should join or leave queue
  
  ### leave_ready_queue
  - Takes employee_id and store_id as parameters
  - Removes employee from the ready queue
  - Returns void

  ## Security
  - Functions are accessible to all users (matches existing RLS policy)
  - Only affects the specified employee's queue status
*/

-- Function: Check if employee is in ready queue
CREATE OR REPLACE FUNCTION check_queue_status(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_in_queue boolean;
BEGIN
  SELECT EXISTS(
    SELECT 1 
    FROM technician_ready_queue
    WHERE employee_id = p_employee_id
      AND store_id = p_store_id
      AND status = 'ready'
  ) INTO v_in_queue;
  
  RETURN v_in_queue;
END;
$$;

-- Function: Leave ready queue
CREATE OR REPLACE FUNCTION leave_ready_queue(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Remove employee from ready queue
  DELETE FROM technician_ready_queue
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id;
END;
$$;