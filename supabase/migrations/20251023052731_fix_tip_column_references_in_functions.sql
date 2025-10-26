/*
  # Fix Tip Column References in Database Functions

  ## Overview
  After renaming tip_customer to tip_customer_cash, update all database functions
  to use the new column names and aggregate both cash and card tips.

  ## Changes
  1. Update `get_pending_approvals_for_management` function
     - Replace tip_customer with (tip_customer_cash + tip_customer_card)
     - Keep tip_receptionist as is (only cash tips for receptionist)
  
  2. Update `get_pending_approvals_for_technician` function
     - Replace tip_customer with (tip_customer_cash + tip_customer_card)
     - Keep tip_receptionist as is

  ## Notes
  - Total customer tips now include both cash and card amounts
  - Receptionist tips remain cash-only (tip_receptionist_card was removed)
*/

-- Update get_pending_approvals_for_management function
DROP FUNCTION IF EXISTS get_pending_approvals_for_management(uuid);

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
  technician_names text,
  reason text
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
    SUM(COALESCE(ti.tip_customer_cash, 0) + COALESCE(ti.tip_customer_card, 0)) as tip_customer,
    SUM(COALESCE(ti.tip_receptionist, 0)) as tip_receptionist,
    st.payment_method,
    COALESCE(st.requires_higher_approval, false) as requires_higher_approval,
    STRING_AGG(DISTINCT emp.display_name, ', ') as technician_names,
    CASE 
      WHEN COALESCE(st.requires_higher_approval, false) = true THEN 
        'Closed by employee with full ticket control'
      WHEN 'Supervisor' = ANY(ARRAY(SELECT jsonb_array_elements_text(st.closed_by_roles))) THEN
        'Closed by Supervisor'
      ELSE 'Requires review'
    END as reason
  FROM sale_tickets st
  LEFT JOIN employees e ON st.closed_by = e.id
  LEFT JOIN ticket_items ti ON ti.sale_ticket_id = st.id
  LEFT JOIN services s ON ti.service_id = s.id
  LEFT JOIN employees emp ON ti.employee_id = emp.id
  WHERE st.store_id = p_store_id
    AND st.approval_status = 'pending_approval'
    AND st.closed_at IS NOT NULL
    AND st.approval_deadline > NOW()
    AND (
      COALESCE(st.requires_higher_approval, false) = true
      OR 'Supervisor' = ANY(ARRAY(SELECT jsonb_array_elements_text(st.closed_by_roles)))
    )
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- Update get_pending_approvals_for_technician function
DROP FUNCTION IF EXISTS get_pending_approvals_for_technician(uuid, uuid);

CREATE OR REPLACE FUNCTION get_pending_approvals_for_technician(
  p_store_id uuid,
  p_employee_id uuid
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
  technician_names text,
  reason text
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
    SUM(COALESCE(ti.tip_customer_cash, 0) + COALESCE(ti.tip_customer_card, 0)) as tip_customer,
    SUM(COALESCE(ti.tip_receptionist, 0)) as tip_receptionist,
    st.payment_method,
    COALESCE(st.requires_higher_approval, false) as requires_higher_approval,
    STRING_AGG(DISTINCT emp.display_name, ', ') as technician_names,
    'Requires your approval' as reason
  FROM sale_tickets st
  LEFT JOIN employees e ON st.closed_by = e.id
  INNER JOIN ticket_items ti ON ti.sale_ticket_id = st.id
  LEFT JOIN services s ON ti.service_id = s.id
  LEFT JOIN employees emp ON ti.employee_id = emp.id
  WHERE st.store_id = p_store_id
    AND st.approval_status = 'pending_approval'
    AND st.closed_at IS NOT NULL
    AND st.approval_deadline > NOW()
    AND ti.employee_id = p_employee_id
    AND COALESCE(st.requires_higher_approval, false) = false
    AND NOT ('Supervisor' = ANY(ARRAY(SELECT jsonb_array_elements_text(st.closed_by_roles))))
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;
