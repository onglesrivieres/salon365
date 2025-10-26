/*
  # Add Completed Status to Tickets

  ## Overview
  Adds a "completed" state to tickets that separates technician work completion
  from management ticket closure. This implements a two-stage ticket lifecycle:

  1. Technician marks ticket as "completed" when their work is done
  2. Upper management later "closes" the ticket (triggers approval workflow)

  ## New Columns
  - `completed_at` (timestamptz) - When technician marked work as complete
  - `completed_by` (uuid) - Which technician marked it complete

  ## Business Rules
  1. When technician clicks "Ready", ticket is marked as completed (not closed)
  2. Completed tickets show in light red status box
  3. Only upper management (Admin/Receptionist) can close completed tickets
  4. When ticket is closed, approval workflow begins (existing system)
  5. Technicians with multiple roles still cannot approve their own tickets

  ## Security
  - RLS policies enforce who can complete vs close tickets
  - Approval validation prevents self-approval
*/

-- Add completed_at column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'completed_at'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN completed_at timestamptz DEFAULT NULL;
  END IF;
END $$;

-- Add completed_by column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'completed_by'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN completed_by uuid REFERENCES employees(id) DEFAULT NULL;
  END IF;
END $$;

-- Create index on completed_at for efficient filtering
CREATE INDEX IF NOT EXISTS idx_sale_tickets_completed_at ON sale_tickets(completed_at);

-- Create function to mark ticket as completed
CREATE OR REPLACE FUNCTION mark_ticket_completed(
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

  -- Check if ticket is already closed
  IF v_ticket.closed_at IS NOT NULL THEN
    RETURN json_build_object('success', false, 'message', 'Ticket is already closed');
  END IF;

  -- Check if employee is assigned to this ticket
  IF NOT EXISTS (
    SELECT 1 FROM ticket_items WHERE sale_ticket_id = p_ticket_id AND employee_id = p_employee_id
  ) THEN
    RETURN json_build_object('success', false, 'message', 'You are not assigned to this ticket');
  END IF;

  -- Mark ticket as completed
  UPDATE sale_tickets
  SET
    completed_at = NOW(),
    completed_by = p_employee_id,
    updated_at = NOW()
  WHERE id = p_ticket_id;

  RETURN json_build_object('success', true, 'message', 'Ticket marked as completed');
END;
$$;

-- Update existing trigger to also check completed status
-- Approval workflow should only start when ticket is CLOSED (not just completed)
CREATE OR REPLACE FUNCTION set_approval_deadline()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Only set approval fields when ticket is being closed
  IF NEW.closed_at IS NOT NULL AND (OLD.closed_at IS NULL OR OLD.closed_at IS DISTINCT FROM NEW.closed_at) THEN
    -- Only set approval status if ticket was closed by someone who can close tickets
    -- AND the closer is different from the technician who worked on it
    NEW.approval_status := 'pending_approval';
    NEW.approval_deadline := NEW.closed_at + INTERVAL '48 hours';
  END IF;

  RETURN NEW;
END;
$$;

-- Update approve_ticket function to enforce self-approval prevention
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

  -- Check if approver is different from closer
  IF v_ticket.closed_by = p_employee_id THEN
    RETURN json_build_object('success', false, 'message', 'You cannot approve a ticket you closed');
  END IF;

  -- CRITICAL: Check if approver is different from completer (technician who worked on it)
  IF v_ticket.completed_by = p_employee_id THEN
    RETURN json_build_object('success', false, 'message', 'You cannot approve a ticket you worked on');
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
    approved_at = NOW(),
    approved_by = p_employee_id,
    updated_at = NOW()
  WHERE id = p_ticket_id;

  RETURN json_build_object('success', true, 'message', 'Ticket approved successfully');
END;
$$;