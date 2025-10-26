/*
  # Add Missing Ticket Approval Functions

  ## Overview
  This migration adds the missing approve_ticket and reject_ticket functions
  that are required for the approval workflow to work properly.

  ## Functions Created
  
  1. **approve_ticket(p_ticket_id, p_employee_id)**
     - Approves a ticket if the employee is assigned to it
     - Validates that approver != closer (conflict of interest)
     - Sets approval_status to 'approved'
  
  2. **reject_ticket(p_ticket_id, p_employee_id, p_rejection_reason)**
     - Rejects a ticket with a reason
     - Sets requires_admin_review flag
     - Sets approval_status to 'rejected'

  3. **auto_approve_expired_tickets()**
     - Auto-approves tickets past their 48-hour deadline
     - Sets approval_status to 'auto_approved'

  ## Security
  - Functions validate employee assignment to ticket
  - Prevents conflict of interest (closer cannot approve)
  - Activity logging handled in application layer
*/

-- Create function to approve a ticket
CREATE OR REPLACE FUNCTION approve_ticket(
  p_ticket_id uuid,
  p_employee_id uuid
)
RETURNS json AS $$
DECLARE
  v_ticket sale_tickets;
  v_result json;
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
  
  -- Check if approver is different from closer
  IF v_ticket.closed_by = p_employee_id THEN
    RETURN json_build_object('success', false, 'message', 'You cannot approve a ticket you closed');
  END IF;
  
  -- Check if employee is assigned to this ticket
  IF NOT EXISTS (
    SELECT 1 FROM ticket_items WHERE sale_ticket_id = p_ticket_id AND employee_id = p_employee_id
  ) THEN
    RETURN json_build_object('success', false, 'message', 'You are not assigned to this ticket');
  END IF;
  
  -- Approve the ticket
  UPDATE sale_tickets
  SET 
    approval_status = 'approved',
    approved_at = now(),
    approved_by = p_employee_id,
    updated_at = now()
  WHERE id = p_ticket_id;
  
  RETURN json_build_object('success', true, 'message', 'Ticket approved successfully');
END;
$$ LANGUAGE plpgsql;

-- Create function to reject a ticket
CREATE OR REPLACE FUNCTION reject_ticket(
  p_ticket_id uuid,
  p_employee_id uuid,
  p_rejection_reason text
)
RETURNS json AS $$
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
  
  -- Check if employee is assigned to this ticket
  IF NOT EXISTS (
    SELECT 1 FROM ticket_items WHERE sale_ticket_id = p_ticket_id AND employee_id = p_employee_id
  ) THEN
    RETURN json_build_object('success', false, 'message', 'You are not assigned to this ticket');
  END IF;
  
  -- Reject the ticket
  UPDATE sale_tickets
  SET 
    approval_status = 'rejected',
    rejection_reason = p_rejection_reason,
    requires_admin_review = true,
    updated_at = now()
  WHERE id = p_ticket_id;
  
  RETURN json_build_object('success', true, 'message', 'Ticket rejected and sent for admin review');
END;
$$ LANGUAGE plpgsql;

-- Create function to auto-approve expired tickets
CREATE OR REPLACE FUNCTION auto_approve_expired_tickets()
RETURNS json AS $$
DECLARE
  v_count integer;
BEGIN
  -- Auto-approve tickets past their deadline
  UPDATE sale_tickets
  SET 
    approval_status = 'auto_approved',
    approved_at = now(),
    updated_at = now()
  WHERE approval_status = 'pending_approval'
    AND approval_deadline < now();
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  
  RETURN json_build_object(
    'success', true, 
    'message', format('Auto-approved %s ticket(s)', v_count),
    'count', v_count
  );
END;
$$ LANGUAGE plpgsql;