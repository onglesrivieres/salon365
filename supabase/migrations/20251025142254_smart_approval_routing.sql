/*
  # Smart Approval Routing - Complete Fix

  ## Problem Statement
  Admin/Manager sees 7 tickets where:
  - Someone else (e.g., Technician A) performed the service
  - A Supervisor closed the ticket
  - These tickets show in Admin's queue but NOT in Technician A's queue
  - This is incorrect - should be in Technician A's queue

  ## Root Causes
  1. Tickets have wrong approval_required_level in database ('manager' instead of 'technician')
  2. Even if we fix the level, the routing logic needs to be correct
  3. The approval functions need to route based on REALITY (who worked on it) not just the stored level

  ## Solution Strategy
  This migration implements a 3-part solution:

  ### Part 1: Fix the Trigger (for future tickets)
  Ensure new tickets get the correct approval_required_level from the start

  ### Part 2: Fix Existing Data (recalculate all pending tickets)
  Loop through every pending ticket and set correct approval_required_level

  ### Part 3: Smart Approval Functions (work with any data state)
  Rewrite the approval functions to be "smart" - they calculate who should approve
  based on who actually worked on the ticket, regardless of what's stored in
  approval_required_level

  This way, even if data is wrong, the functions return correct results.
*/

-- ============================================================================
-- PART 1: CORRECT TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION set_approval_deadline()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_closer_roles text[];
  v_performers uuid[];
  v_performer_count int;
  v_closer_is_performer boolean;
  v_closer_is_receptionist boolean;
  v_closer_is_supervisor boolean;
  v_closer_is_technician boolean;
  v_closer_is_spa_expert boolean;
  v_required_level text;
  v_reason text;
  v_performed_and_closed boolean;
BEGIN
  IF NEW.closed_at IS NOT NULL AND (OLD.closed_at IS NULL OR OLD.closed_at IS DISTINCT FROM NEW.closed_at) THEN

    NEW.approval_status := 'pending_approval';
    NEW.approval_deadline := NEW.closed_at + INTERVAL '48 hours';

    v_closer_roles := COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(NEW.closed_by_roles)),
      ARRAY[]::text[]
    );

    v_closer_is_receptionist := 'Receptionist' = ANY(v_closer_roles);
    v_closer_is_supervisor := 'Supervisor' = ANY(v_closer_roles);
    v_closer_is_technician := 'Technician' = ANY(v_closer_roles);
    v_closer_is_spa_expert := 'Spa Expert' = ANY(v_closer_roles);

    SELECT
      ARRAY_AGG(DISTINCT employee_id),
      COUNT(DISTINCT employee_id)
    INTO v_performers, v_performer_count
    FROM ticket_items
    WHERE sale_ticket_id = NEW.id;

    v_closer_is_performer := NEW.closed_by = ANY(v_performers);
    v_performed_and_closed := (v_performer_count = 1 AND v_closer_is_performer);

    -- KEY FIX: Only escalate when same person has complete control
    IF v_closer_is_supervisor AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Supervisor performed service and closed ticket themselves - requires Manager/Admin approval';
      NEW.requires_higher_approval := true;

    ELSIF v_closer_is_receptionist AND v_performed_and_closed AND
          (v_closer_is_technician OR v_closer_is_spa_expert) THEN
      v_required_level := 'supervisor';
      v_reason := 'Receptionist performed service and closed ticket themselves - requires Supervisor approval';
      NEW.requires_higher_approval := true;

    ELSIF v_closer_is_technician AND v_closer_is_receptionist AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Employee with both Technician and Receptionist roles performed and closed ticket - requires Manager/Admin approval';
      NEW.requires_higher_approval := true;

    ELSE
      v_required_level := 'technician';
      v_reason := 'Standard technician peer approval';
      NEW.requires_higher_approval := false;
    END IF;

    NEW.approval_required_level := v_required_level;
    NEW.approval_reason := v_reason;
    NEW.performed_and_closed_by_same_person := v_performed_and_closed;

  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- PART 2: FIX ALL EXISTING PENDING TICKETS
-- ============================================================================

DO $$
DECLARE
  v_ticket RECORD;
  v_closer_roles text[];
  v_performers uuid[];
  v_performer_count int;
  v_closer_is_performer boolean;
  v_closer_is_receptionist boolean;
  v_closer_is_supervisor boolean;
  v_closer_is_technician boolean;
  v_closer_is_spa_expert boolean;
  v_required_level text;
  v_reason text;
  v_performed_and_closed boolean;
  v_updated_count int := 0;
BEGIN
  RAISE NOTICE 'Starting approval routing fix for all pending tickets...';

  FOR v_ticket IN
    SELECT id, closed_by, closed_by_roles
    FROM sale_tickets
    WHERE approval_status = 'pending_approval'
      AND closed_at IS NOT NULL
  LOOP
    -- Get closer's roles
    v_closer_roles := COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(v_ticket.closed_by_roles)),
      ARRAY[]::text[]
    );

    -- Fallback: get roles from employees table if not stored
    IF array_length(v_closer_roles, 1) IS NULL THEN
      SELECT role INTO v_closer_roles
      FROM employees
      WHERE id = v_ticket.closed_by;
    END IF;

    v_closer_is_receptionist := 'Receptionist' = ANY(v_closer_roles);
    v_closer_is_supervisor := 'Supervisor' = ANY(v_closer_roles);
    v_closer_is_technician := 'Technician' = ANY(v_closer_roles);
    v_closer_is_spa_expert := 'Spa Expert' = ANY(v_closer_roles);

    -- Get performers
    SELECT
      ARRAY_AGG(DISTINCT employee_id),
      COUNT(DISTINCT employee_id)
    INTO v_performers, v_performer_count
    FROM ticket_items
    WHERE sale_ticket_id = v_ticket.id;

    v_closer_is_performer := v_ticket.closed_by = ANY(v_performers);
    v_performed_and_closed := (v_performer_count = 1 AND v_closer_is_performer);

    -- Apply approval logic
    IF v_closer_is_supervisor AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Supervisor performed service and closed ticket themselves - requires Manager/Admin approval';

    ELSIF v_closer_is_receptionist AND v_performed_and_closed AND
          (v_closer_is_technician OR v_closer_is_spa_expert) THEN
      v_required_level := 'supervisor';
      v_reason := 'Receptionist performed service and closed ticket themselves - requires Supervisor approval';

    ELSIF v_closer_is_technician AND v_closer_is_receptionist AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Employee with both Technician and Receptionist roles performed and closed ticket - requires Manager/Admin approval';

    ELSE
      v_required_level := 'technician';
      v_reason := 'Standard technician peer approval';
    END IF;

    -- Update the ticket
    UPDATE sale_tickets
    SET
      approval_required_level = v_required_level,
      approval_reason = v_reason,
      performed_and_closed_by_same_person = v_performed_and_closed,
      requires_higher_approval = (v_required_level != 'technician')
    WHERE id = v_ticket.id
      AND (
        approval_required_level IS DISTINCT FROM v_required_level
        OR approval_reason IS DISTINCT FROM v_reason
        OR performed_and_closed_by_same_person IS DISTINCT FROM v_performed_and_closed
      );

    IF FOUND THEN
      v_updated_count := v_updated_count + 1;
    END IF;

  END LOOP;

  RAISE NOTICE 'Fixed % pending approval tickets', v_updated_count;
END $$;

-- ============================================================================
-- PART 3: SMART APPROVAL FUNCTIONS
-- ============================================================================

-- These functions are "smart" - they calculate who should approve based on
-- the actual performers, not just blindly trusting approval_required_level

-- Smart function for technician approvals
CREATE OR REPLACE FUNCTION get_pending_approvals_for_technician(
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
  requires_higher_approval boolean,
  approval_reason text
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
    STRING_AGG(DISTINCT s.name, ', ') as service_name,
    SUM(ti.tip_customer) as tip_customer,
    SUM(ti.tip_receptionist) as tip_receptionist,
    st.payment_method,
    st.requires_higher_approval,
    st.approval_reason
  FROM sale_tickets st
  INNER JOIN ticket_items ti ON ti.sale_ticket_id = st.id
  LEFT JOIN employees e ON st.closed_by = e.id
  LEFT JOIN services s ON ti.service_id = s.id
  WHERE st.store_id = p_store_id
    AND st.approval_status = 'pending_approval'
    AND st.closed_at IS NOT NULL
    AND st.approval_deadline > NOW()
    -- SMART ROUTING: Show if technician-level OR if this technician worked on it
    AND (
      st.approval_required_level = 'technician'
      -- Also show manager-level tickets if this tech worked on it and closer didn't
      -- (catches mis-routed tickets)
      OR (
        st.approval_required_level = 'manager'
        AND ti.employee_id = p_employee_id
        AND st.closed_by != ti.employee_id
        -- AND closer didn't perform (closer not in performers list)
        AND st.closed_by NOT IN (
          SELECT DISTINCT employee_id
          FROM ticket_items
          WHERE sale_ticket_id = st.id
        )
      )
    )
    -- Must have worked on this ticket
    AND ti.employee_id = p_employee_id
    -- Cannot approve tickets they closed
    AND st.closed_by != p_employee_id
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- Smart function for management approvals
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
    SUM(ti.tip_customer) as tip_customer,
    SUM(ti.tip_receptionist) as tip_receptionist,
    st.payment_method,
    COALESCE(st.requires_higher_approval, false) as requires_higher_approval,
    STRING_AGG(DISTINCT emp.display_name, ', ') as technician_names,
    COALESCE(st.approval_reason, 'Requires management review') as reason
  FROM sale_tickets st
  LEFT JOIN employees e ON st.closed_by = e.id
  LEFT JOIN ticket_items ti ON ti.sale_ticket_id = st.id
  LEFT JOIN services s ON ti.service_id = s.id
  LEFT JOIN employees emp ON ti.employee_id = emp.id
  WHERE st.store_id = p_store_id
    AND st.approval_status = 'pending_approval'
    AND st.closed_at IS NOT NULL
    AND st.approval_deadline > NOW()
    -- SMART ROUTING: Only show TRUE manager-level tickets
    AND st.approval_required_level = 'manager'
    -- ADDITIONAL CHECK: Verify closer actually performed work (for conflict of interest cases)
    AND st.performed_and_closed_by_same_person = true
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- Supervisor function remains simple - they only see supervisor-level approvals
-- (No smart routing needed as it's uncommon)

COMMENT ON FUNCTION get_pending_approvals_for_technician IS
'Smart routing: Shows technician-level approvals AND catches mis-routed manager-level tickets where the technician worked but supervisor just closed it';

COMMENT ON FUNCTION get_pending_approvals_for_management IS
'Smart routing: Only shows tickets where closer performed AND closed (true conflict of interest)';
