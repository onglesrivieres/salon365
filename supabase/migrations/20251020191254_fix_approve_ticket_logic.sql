/*
  # Fix Approve Ticket Logic

  ## Overview
  Fixes the `approve_ticket` function to implement the correct approval workflow:
  - Technicians MUST approve tickets they worked on (have ticket_items)
  - Technicians CANNOT approve tickets they closed (to prevent manipulation)
  
  ## Problem
  The previous version had contradictory logic:
  - Line 145: Prevented approving tickets you worked on
  - Line 150: Required that you ARE assigned to the ticket
  - These two checks contradict each other!

  ## Solution
  Remove the incorrect check that prevents approving tickets you worked on.
  Keep the checks for:
  1. Ticket must be in pending_approval status
  2. Approver cannot be the person who closed the ticket
  3. Approver must be assigned to the ticket (have ticket_items)

  ## Security
  - Maintains separation of duties (closer != approver)
  - Ensures technicians only approve their own work
  - Prevents manipulation and fraud
*/

DROP FUNCTION IF EXISTS approve_ticket(uuid, uuid);

CREATE OR REPLACE FUNCTION approve_ticket(
  p_ticket_id uuid,
  p_employee_id uuid
)
RETURNS json
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ticket sale_tickets;
BEGIN
  -- Get the ticket
  SELECT * INTO v_ticket FROM sale_tickets WHERE id = p_ticket_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'Ticket not found');
  END IF;

  -- Check if ticket is in pending_approval status
  IF v_ticket.approval_status != 'pending_approval' THEN
    RETURN json_build_object('success', false, 'message', 'Ticket is not pending approval');
  END IF;

  -- Check if approver is different from closer (to prevent manipulation)
  IF v_ticket.closed_by = p_employee_id THEN
    RETURN json_build_object('success', false, 'message', 'You cannot approve a ticket you closed');
  END IF;

  -- Check if employee is assigned to this ticket (they worked on it)
  IF NOT EXISTS (
    SELECT 1 FROM ticket_items WHERE sale_ticket_id = p_ticket_id AND employee_id = p_employee_id
  ) THEN
    RETURN json_build_object('success', false, 'message', 'You are not assigned to this ticket');
  END IF;

  -- Approve the ticket
  UPDATE sale_tickets
  SET
    approval_status = 'approved',
    approved_at = NOW(),
    approved_by = p_employee_id,
    updated_at = NOW()
  WHERE id = p_ticket_id;

  RETURN json_build_object('success', true, 'message', 'Ticket approved successfully');
END;
$$;