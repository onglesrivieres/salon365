/*
  # Fix Pending Approvals for Technician Function

  ## Overview
  Updates the `get_pending_approvals_for_technician` function to prevent
  manipulation and cheating by ensuring technicians:
  1. Can only approve tickets they worked on (have ticket_items assigned to them)
  2. Cannot approve tickets they themselves closed (to avoid conflict of interest)

  ## Changes
  The function now:
  - Filters tickets where the technician has ticket_items (they worked on it)
  - Excludes tickets where the technician closed the ticket (closed_by != p_employee_id)
  - Only shows tickets in pending_approval status
  - Orders by approval_deadline (most urgent first)

  ## Security
  - Prevents self-approval of tickets the technician closed
  - Ensures technicians only approve work they actually performed
  - Maintains data integrity for the approval workflow
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
  payment_method text
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
    st.payment_method
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
  ORDER BY st.approval_deadline ASC;
END;
$$;