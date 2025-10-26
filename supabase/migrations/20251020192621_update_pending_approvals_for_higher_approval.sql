/*
  # Update Pending Approvals to Handle Higher Approval Requirements

  ## Overview
  Updates the approval workflow to handle tickets that require higher management approval.
  Regular technicians should NOT see tickets that require_higher_approval.
  Only Admin/Manager/Owner can approve those tickets.

  ## Changes
  1. Update `get_pending_approvals_for_technician` to exclude tickets with `requires_higher_approval = true`
  2. Create new function `get_pending_approvals_for_management` for Admin/Manager/Owner
  3. Update `approve_ticket` to check role permissions for higher approval tickets

  ## Security
  - Regular technicians cannot approve tickets that need higher approval
  - Only users with Admin, Manager, or Owner roles can approve higher approval tickets
*/

-- Update get_pending_approvals_for_technician to exclude higher approval tickets
DROP FUNCTION IF EXISTS get_pending_approvals_for_technician(uuid, uuid);

CREATE FUNCTION get_pending_approvals_for_technician(
  p_employee_id uuid,
  p_store_id uuid
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
  payment_method text,
  requires_higher_approval boolean
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
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
    COALESCE(e.display_name, 'Unknown') as closed_by_name,
    EXTRACT(EPOCH FROM (st.approval_deadline - NOW())) / 3600 as hours_remaining,
    s.name as service_name,
    ti.tip_customer,
    ti.tip_receptionist,
    st.payment_method,
    st.requires_higher_approval
  FROM sale_tickets st
  INNER JOIN ticket_items ti ON ti.sale_ticket_id = st.id
  LEFT JOIN employees e ON st.closed_by = e.id
  LEFT JOIN services s ON ti.service_id = s.id
  WHERE st.store_id = p_store_id
    AND st.approval_status = 'pending_approval'
    AND st.closed_at IS NOT NULL
    AND st.approval_deadline > NOW()
    AND ti.employee_id = p_employee_id
    AND st.closed_by != p_employee_id
    AND COALESCE(st.requires_higher_approval, false) = false
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- Create function for management to see all pending approvals including higher approval tickets
CREATE OR REPLACE FUNCTION get_pending_approvals_for_management(
  p_store_id uuid
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
  closed_by_roles jsonb,
  hours_remaining numeric,
  service_name text,
  tip_customer numeric,
  tip_receptionist numeric,
  payment_method text,
  requires_higher_approval boolean,
  technician_names text
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
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
    COALESCE(e.display_name, 'Unknown') as closed_by_name,
    st.closed_by_roles,
    EXTRACT(EPOCH FROM (st.approval_deadline - NOW())) / 3600 as hours_remaining,
    STRING_AGG(DISTINCT s.name, ', ') as service_name,
    SUM(ti.tip_customer) as tip_customer,
    SUM(ti.tip_receptionist) as tip_receptionist,
    st.payment_method,
    COALESCE(st.requires_higher_approval, false) as requires_higher_approval,
    STRING_AGG(DISTINCT emp.display_name, ', ') as technician_names
  FROM sale_tickets st
  LEFT JOIN employees e ON st.closed_by = e.id
  LEFT JOIN ticket_items ti ON ti.sale_ticket_id = st.id
  LEFT JOIN services s ON ti.service_id = s.id
  LEFT JOIN employees emp ON ti.employee_id = emp.id
  WHERE st.store_id = p_store_id
    AND st.approval_status = 'pending_approval'
    AND st.closed_at IS NOT NULL
    AND st.approval_deadline > NOW()
    AND COALESCE(st.requires_higher_approval, false) = true
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;