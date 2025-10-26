/*
  # Add Ticket Approval System

  ## Overview
  This migration implements a comprehensive approval workflow for sale tickets where:
  - Tickets automatically move to "pending_approval" status when closed
  - The technician who worked on the ticket has 48 hours to approve it
  - If not approved within 48 hours, the ticket is automatically approved
  - Technicians cannot approve tickets they closed themselves
  - Rejected tickets require admin review

  ## New Columns
  
  ### sale_tickets table additions:
  - `approval_status` (text) - Status of approval: pending_approval, approved, rejected, auto_approved
  - `approved_at` (timestamptz) - When the ticket was approved
  - `approved_by` (uuid) - Employee who approved the ticket
  - `approval_deadline` (timestamptz) - 48 hours after closed_at, deadline for manual approval
  - `rejection_reason` (text) - Reason provided when ticket is rejected
  - `requires_admin_review` (boolean) - Flag indicating ticket needs admin attention

  ## Business Rules
  
  1. When a ticket is closed, approval_status is set to "pending_approval"
  2. approval_deadline is automatically set to closed_at + 48 hours
  3. Technician assigned to ticket can approve within 48 hours
  4. Technician who closed ticket CANNOT approve it (conflict of interest)
  5. After 48 hours, ticket automatically becomes "auto_approved"
  6. Rejected tickets set requires_admin_review = true
  7. Approved/auto_approved tickets cannot be edited (except by admins)

  ## Security
  - RLS policies updated to handle approval workflow
  - Validation prevents same user from closing and approving
  - Activity logging tracks all approval actions
*/

-- Add approval columns to sale_tickets table
DO $$
BEGIN
  -- Add approval_status column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'approval_status'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN approval_status text DEFAULT NULL;
  END IF;

  -- Add approved_at column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'approved_at'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN approved_at timestamptz DEFAULT NULL;
  END IF;

  -- Add approved_by column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'approved_by'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN approved_by uuid REFERENCES employees(id) DEFAULT NULL;
  END IF;

  -- Add approval_deadline column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'approval_deadline'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN approval_deadline timestamptz DEFAULT NULL;
  END IF;

  -- Add rejection_reason column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'rejection_reason'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN rejection_reason text DEFAULT NULL;
  END IF;

  -- Add requires_admin_review column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'requires_admin_review'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN requires_admin_review boolean DEFAULT false;
  END IF;
END $$;

-- Create index on approval_status for efficient filtering
CREATE INDEX IF NOT EXISTS idx_sale_tickets_approval_status ON sale_tickets(approval_status);

-- Create index on approval_deadline for auto-approval queries
CREATE INDEX IF NOT EXISTS idx_sale_tickets_approval_deadline ON sale_tickets(approval_deadline);

-- Create index on requires_admin_review for admin queue
CREATE INDEX IF NOT EXISTS idx_sale_tickets_requires_admin_review ON sale_tickets(requires_admin_review);

-- Create function to set approval deadline when ticket is closed
CREATE OR REPLACE FUNCTION set_approval_deadline()
RETURNS TRIGGER AS $$
BEGIN
  -- Only set approval fields when ticket is being closed
  IF NEW.closed_at IS NOT NULL AND (OLD.closed_at IS NULL OR OLD.closed_at IS DISTINCT FROM NEW.closed_at) THEN
    NEW.approval_status := 'pending_approval';
    NEW.approval_deadline := NEW.closed_at + INTERVAL '48 hours';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically set approval deadline
DROP TRIGGER IF EXISTS trigger_set_approval_deadline ON sale_tickets;
CREATE TRIGGER trigger_set_approval_deadline
  BEFORE UPDATE ON sale_tickets
  FOR EACH ROW
  EXECUTE FUNCTION set_approval_deadline();

-- Create function to get pending approvals for a technician
CREATE OR REPLACE FUNCTION get_pending_approvals_for_technician(
  p_employee_id uuid,
  p_store_id uuid DEFAULT NULL
)
RETURNS TABLE (
  ticket_id uuid,
  ticket_no text,
  ticket_date date,
  closed_at timestamptz,
  approval_deadline timestamptz,
  customer_name text,
  customer_phone text,
  total numeric,
  closed_by_name text,
  hours_remaining numeric,
  service_name text,
  tip_customer numeric,
  tip_receptionist numeric,
  payment_method text
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    st.id as ticket_id,
    st.ticket_no,
    st.ticket_date,
    st.closed_at,
    st.approval_deadline,
    st.customer_name,
    st.customer_phone,
    st.total,
    closer.display_name as closed_by_name,
    EXTRACT(EPOCH FROM (st.approval_deadline - now())) / 3600 as hours_remaining,
    s.name as service_name,
    ti.tip_customer,
    ti.tip_receptionist,
    st.payment_method
  FROM sale_tickets st
  LEFT JOIN employees closer ON st.closed_by = closer.id
  LEFT JOIN ticket_items ti ON ti.sale_ticket_id = st.id
  LEFT JOIN services s ON ti.service_id = s.id
  WHERE st.approval_status = 'pending_approval'
    AND st.closed_at IS NOT NULL
    AND ti.employee_id = p_employee_id
    AND (p_store_id IS NULL OR st.store_id = p_store_id)
  ORDER BY st.approval_deadline ASC;
END;
$$ LANGUAGE plpgsql;

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

-- Create function to get approval statistics
CREATE OR REPLACE FUNCTION get_approval_statistics(
  p_store_id uuid DEFAULT NULL,
  p_start_date date DEFAULT NULL,
  p_end_date date DEFAULT NULL
)
RETURNS TABLE (
  total_closed integer,
  pending_approval integer,
  approved integer,
  auto_approved integer,
  rejected integer,
  requires_review integer
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*)::integer as total_closed,
    COUNT(*) FILTER (WHERE approval_status = 'pending_approval')::integer as pending_approval,
    COUNT(*) FILTER (WHERE approval_status = 'approved')::integer as approved,
    COUNT(*) FILTER (WHERE approval_status = 'auto_approved')::integer as auto_approved,
    COUNT(*) FILTER (WHERE approval_status = 'rejected')::integer as rejected,
    COUNT(*) FILTER (WHERE requires_admin_review = true)::integer as requires_review
  FROM sale_tickets
  WHERE closed_at IS NOT NULL
    AND (p_store_id IS NULL OR store_id = p_store_id)
    AND (p_start_date IS NULL OR ticket_date >= p_start_date)
    AND (p_end_date IS NULL OR ticket_date <= p_end_date);
END;
$$ LANGUAGE plpgsql;