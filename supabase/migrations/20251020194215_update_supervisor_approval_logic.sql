/*
  # Update Supervisor Approval Logic

  ## Overview
  Refines approval logic for Supervisors to handle two scenarios:
  
  1. Supervisor worked on ticket + Supervisor closed ticket
     → Requires Admin/Manager approval (prevent self-approval)
  
  2. Supervisor worked on ticket + Receptionist closed ticket
     → Supervisor CAN approve (normal technician approval flow)

  ## Business Rules
  - If a Supervisor worked on a ticket that was closed by ANY Supervisor, they cannot approve it
  - This prevents Supervisors from approving tickets they had complete control over
  - However, if a Receptionist closed the ticket, Supervisors can approve normally
  
  ## Changes
  - Update approve_ticket function to check if approver is Supervisor
  - Check if closer was also a Supervisor
  - If both conditions true, require management approval

  ## Security
  - Maintains separation of duties
  - Prevents Supervisors from self-approving their complete work
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
  v_closer_roles text[];
  v_approver_is_supervisor boolean;
  v_closed_by_supervisor boolean;
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

  -- Get closer's roles from the stored closed_by_roles
  v_closer_roles := ARRAY(SELECT jsonb_array_elements_text(v_ticket.closed_by_roles));

  -- Check if approver is a Supervisor
  v_approver_is_supervisor := 'Supervisor' = ANY(v_approver_roles);

  -- Check if closer was a Supervisor
  v_closed_by_supervisor := 'Supervisor' = ANY(v_closer_roles);

  -- Special logic for Supervisors
  IF v_approver_is_supervisor AND v_closed_by_supervisor THEN
    -- Check if this Supervisor worked on the ticket
    IF EXISTS (
      SELECT 1 FROM ticket_items WHERE sale_ticket_id = p_ticket_id AND employee_id = p_employee_id
    ) THEN
      -- Supervisor worked on ticket that was closed by a Supervisor
      -- This requires higher approval to prevent self-approval scenario
      RETURN json_build_object(
        'success', false, 
        'message', 'This ticket requires approval from management. It was worked on and closed by Supervisors.'
      );
    END IF;
  END IF;

  -- Check if ticket requires higher approval (dual-role or Supervisor closer)
  IF COALESCE(v_ticket.requires_higher_approval, false) = true THEN
    -- Only Admin, Manager, or Owner can approve these tickets
    IF NOT (v_approver_roles && ARRAY['Owner', 'Manager']::text[]) THEN
      RETURN json_build_object(
        'success', false, 
        'message', 'This ticket requires approval from management (Admin/Manager/Owner). It was closed by someone with full control over the ticket lifecycle.'
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