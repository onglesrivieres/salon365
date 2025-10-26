/*
  # Fix Supervisor Approval Routing - Final Solution

  ## Problem
  Admin sees tickets where Supervisor closed but did NOT perform the work.
  These should go to technicians who performed, not management.

  ## Root Cause
  Current logic:
  - Management: Shows if closed_by_roles contains 'Supervisor' (WRONG)
  - Technician: Excludes if closed_by_roles contains 'Supervisor' (WRONG)

  This routes ALL supervisor-closed tickets to management, regardless of who worked.

  ## Correct Logic
  Management should only see tickets where:
  - requires_higher_approval = true (conflict of interest cases)
  - AND closer actually performed the work

  Technicians should see tickets where:
  - They worked on it
  - requires_higher_approval = false (normal peer approval)
  - Even if supervisor closed it (as long as supervisor didn't perform)

  ## Solution
  1. Update get_pending_approvals_for_management to check if closer performed work
  2. Update get_pending_approvals_for_technician to remove supervisor exclusion
  3. Update trigger to set requires_higher_approval correctly
*/

-- ============================================================================
-- FIX THE TRIGGER TO SET requires_higher_approval CORRECTLY
-- ============================================================================

CREATE OR REPLACE FUNCTION set_approval_deadline()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_closer_roles text[];
  v_performer_count int;
  v_closer_performed boolean;
  v_is_supervisor boolean;
  v_is_receptionist boolean;
  v_is_technician boolean;
  v_is_spa_expert boolean;
BEGIN
  -- Only process when ticket is closed for the first time
  IF NEW.closed_at IS NOT NULL AND (OLD.closed_at IS NULL OR OLD.closed_at IS DISTINCT FROM NEW.closed_at) THEN
    
    -- Set basic approval info
    NEW.approval_status := 'pending_approval';
    NEW.approval_deadline := NEW.closed_at + INTERVAL '48 hours';

    -- Get closer's roles
    v_closer_roles := COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(NEW.closed_by_roles)),
      ARRAY[]::text[]
    );

    v_is_supervisor := 'Supervisor' = ANY(v_closer_roles);
    v_is_receptionist := 'Receptionist' = ANY(v_closer_roles);
    v_is_technician := 'Technician' = ANY(v_closer_roles);
    v_is_spa_expert := 'Spa Expert' = ANY(v_closer_roles);

    -- Count performers and check if closer performed
    SELECT 
      COUNT(DISTINCT employee_id),
      NEW.closed_by IN (SELECT DISTINCT employee_id FROM ticket_items WHERE sale_ticket_id = NEW.id)
    INTO v_performer_count, v_closer_performed
    FROM ticket_items
    WHERE sale_ticket_id = NEW.id;

    /*
      Set requires_higher_approval = true ONLY when:
      1. Supervisor performed AND closed (alone)
      2. Receptionist with tech role performed AND closed (alone)
      3. Dual-role Tech+Receptionist performed AND closed (alone)

      Otherwise requires_higher_approval = false (technician approval)
    */

    IF v_closer_performed AND v_performer_count = 1 THEN
      -- One person did everything - check for conflicts
      IF v_is_supervisor THEN
        -- Supervisor did everything - needs manager approval
        NEW.requires_higher_approval := true;
      ELSIF v_is_receptionist AND (v_is_technician OR v_is_spa_expert) THEN
        -- Receptionist with service role did everything - needs supervisor approval
        NEW.requires_higher_approval := true;
      ELSIF v_is_technician AND v_is_receptionist THEN
        -- Dual role did everything - needs manager approval
        NEW.requires_higher_approval := true;
      ELSE
        -- Regular technician did everything - still needs peer approval
        NEW.requires_higher_approval := false;
      END IF;
    ELSE
      -- Normal case: different people performed vs closed, OR multiple performers
      -- This is proper separation of duties - technician approval
      NEW.requires_higher_approval := false;
    END IF;

  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- FIX MANAGEMENT APPROVAL FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION get_pending_approvals_for_management(p_store_id uuid)
RETURNS TABLE(
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
        'Employee performed and closed ticket - requires higher approval'
      ELSE 
        'Requires review'
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
    -- ONLY show tickets that truly require higher approval
    AND COALESCE(st.requires_higher_approval, false) = true
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- ============================================================================
-- FIX TECHNICIAN APPROVAL FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION get_pending_approvals_for_technician(
  p_store_id uuid,
  p_employee_id uuid
)
RETURNS TABLE(
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
    -- Show if this technician worked on it
    AND ti.employee_id = p_employee_id
    -- Don't show if they closed it (can't self-approve)
    AND st.closed_by != p_employee_id
    -- Show normal technician approvals (not escalated to management)
    AND COALESCE(st.requires_higher_approval, false) = false
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- ============================================================================
-- FIX EXISTING TICKETS
-- ============================================================================

-- Recalculate requires_higher_approval for all pending tickets
UPDATE sale_tickets st
SET requires_higher_approval = (
  -- Check if closer performed AND was the only performer
  CASE
    WHEN (
      st.closed_by IN (SELECT DISTINCT employee_id FROM ticket_items WHERE sale_ticket_id = st.id)
      AND (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = st.id) = 1
      AND (
        -- And closer has a role that requires escalation
        st.closed_by_roles @> '["Supervisor"]'::jsonb
        OR (
          st.closed_by_roles @> '["Receptionist"]'::jsonb 
          AND (
            st.closed_by_roles @> '["Technician"]'::jsonb
            OR st.closed_by_roles @> '["Spa Expert"]'::jsonb
          )
        )
        OR (
          st.closed_by_roles @> '["Technician"]'::jsonb
          AND st.closed_by_roles @> '["Receptionist"]'::jsonb
        )
      )
    ) THEN true
    ELSE false
  END
)
WHERE st.approval_status = 'pending_approval'
  AND st.closed_at IS NOT NULL;
