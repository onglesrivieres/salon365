/*
  # Update Approve Ticket Function for Higher Approval Requirements

  ## Overview
  Updates the approve_ticket function to enforce higher approval requirements.
  Tickets closed by dual-role technicians (with receptionist permissions) can only
  be approved by Admin, Manager, or Owner.

  ## Changes
  - Check if ticket requires_higher_approval
  - If yes, verify approver has Admin, Manager, or Owner role
  - Regular technicians cannot approve these tickets

  ## Security
  - Prevents approval by unauthorized roles
  - Enforces separation of duties for sensitive tickets
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
  v_approver_roles text[];
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

  -- Get approver's roles
  SELECT role INTO v_approver_roles FROM employees WHERE id = p_employee_id;

  IF v_approver_roles IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Approver not found');
  END IF;

  -- Check if ticket requires higher approval
  IF COALESCE(v_ticket.requires_higher_approval, false) = true THEN
    -- Only Admin, Manager, or Owner can approve these tickets
    IF NOT (v_approver_roles && ARRAY['Owner', 'Manager']::text[]) THEN
      RETURN json_build_object(
        'success', false, 
        'message', 'This ticket requires approval from management (Admin/Manager/Owner). It was closed by someone with both Technician and Receptionist roles.'
      );
    END IF;
  ELSE
    -- Regular approval: check if employee is assigned to this ticket (they worked on it)
    IF NOT EXISTS (
      SELECT 1 FROM ticket_items WHERE sale_ticket_id = p_ticket_id AND employee_id = p_employee_id
    ) THEN
      RETURN json_build_object('success', false, 'message', 'You are not assigned to this ticket');
    END IF;
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