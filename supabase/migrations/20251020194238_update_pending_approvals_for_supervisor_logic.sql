/*
  # Update Pending Approvals for Supervisor Logic

  ## Overview
  Updates the get_pending_approvals_for_technician function to handle Supervisor scenarios correctly:
  
  1. If approver is a Supervisor AND ticket was closed by a Supervisor
     → Do NOT show in pending approvals (requires management)
  
  2. If approver is a Supervisor AND ticket was closed by Receptionist
     → Show in pending approvals (Supervisor can approve)

  ## Changes
  - Add check for Supervisor role in approver's roles
  - Add check for Supervisor role in closer's roles (from closed_by_roles)
  - Filter out tickets where both are true

  ## Security
  - Prevents Supervisors from seeing tickets they cannot approve
  - Ensures proper escalation to management
*/

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
DECLARE
  v_employee_roles text[];
  v_is_supervisor boolean;
BEGIN
  -- Get the employee's roles
  SELECT role INTO v_employee_roles FROM employees WHERE id = p_employee_id;
  
  -- Check if employee is a Supervisor
  v_is_supervisor := 'Supervisor' = ANY(v_employee_roles);

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
    -- If approver is Supervisor and closer is also Supervisor, exclude this ticket
    AND NOT (
      v_is_supervisor = true 
      AND 'Supervisor' = ANY(ARRAY(SELECT jsonb_array_elements_text(st.closed_by_roles)))
    )
  ORDER BY st.approval_deadline ASC;
END;
$$;