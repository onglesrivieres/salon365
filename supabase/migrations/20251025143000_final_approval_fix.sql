/*
  # Final Approval Fix - Absolute Solution

  ## Problem Analysis
  Admin sees 9 tickets that should go to technicians.
  These tickets: Technician performed, Supervisor/other closed.

  ## Root Cause
  Tickets have approval_required_level = 'manager' but should be 'technician'

  ## Requirements (SIMPLIFIED)

  **Who needs to approve?**
  - If closer PERFORMED the work and CLOSED → Higher authority approves
    - Supervisor did both → Manager approves
    - Receptionist (with tech role) did both → Supervisor approves
    - Tech+Receptionist dual-role did both → Manager approves

  - If closer DID NOT perform the work → Tech who performed approves
    - Technician A performed, Receptionist B closed → Tech A approves
    - Technician A performed, Supervisor B closed → Tech A approves
    - Tech A + B performed, Tech A closed → Tech B approves
    - Tech A + B performed, Receptionist closed → Tech A & B approve

  ## Solution
  1. Fix trigger for future tickets
  2. Fix ALL existing tickets
  3. Keep approval functions simple (trust the data)
*/

-- ============================================================================
-- STEP 1: RECREATE TRIGGER WITH CORRECT LOGIC
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
  -- Only process when ticket is closed for the first time
  IF NEW.closed_at IS NOT NULL AND (OLD.closed_at IS NULL OR OLD.closed_at IS DISTINCT FROM NEW.closed_at) THEN

    -- Set basic approval info
    NEW.approval_status := 'pending_approval';
    NEW.approval_deadline := NEW.closed_at + INTERVAL '48 hours';

    -- Get closer's roles from the stored closed_by_roles field
    v_closer_roles := COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(NEW.closed_by_roles)),
      ARRAY[]::text[]
    );

    -- Identify closer's roles
    v_closer_is_receptionist := 'Receptionist' = ANY(v_closer_roles);
    v_closer_is_supervisor := 'Supervisor' = ANY(v_closer_roles);
    v_closer_is_technician := 'Technician' = ANY(v_closer_roles);
    v_closer_is_spa_expert := 'Spa Expert' = ANY(v_closer_roles);

    -- Get all unique performers who worked on this ticket
    SELECT
      ARRAY_AGG(DISTINCT employee_id),
      COUNT(DISTINCT employee_id)
    INTO v_performers, v_performer_count
    FROM ticket_items
    WHERE sale_ticket_id = NEW.id;

    -- Check if closer is one of the performers
    v_closer_is_performer := NEW.closed_by = ANY(v_performers);

    -- This is the KEY: performed_and_closed means ONE person did EVERYTHING
    v_performed_and_closed := (v_performer_count = 1 AND v_closer_is_performer);

    /*
      APPROVAL ROUTING DECISION TREE
      ================================
      The fundamental principle: Escalate ONLY when one person controls both
      the service delivery AND the billing/closing.
    */

    -- CASE 1: Supervisor performed AND closed (alone)
    IF v_closer_is_supervisor AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Supervisor performed and closed ticket - requires Manager approval';
      NEW.requires_higher_approval := true;

    -- CASE 2: Receptionist with service capability performed AND closed (alone)
    ELSIF v_closer_is_receptionist AND v_performed_and_closed AND
          (v_closer_is_technician OR v_closer_is_spa_expert) THEN
      v_required_level := 'supervisor';
      v_reason := 'Receptionist performed and closed ticket - requires Supervisor approval';
      NEW.requires_higher_approval := true;

    -- CASE 3: Dual-role Tech+Receptionist performed AND closed (alone)
    ELSIF v_closer_is_technician AND v_closer_is_receptionist AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Dual-role employee performed and closed ticket - requires Manager approval';
      NEW.requires_higher_approval := true;

    -- CASE 4: All other scenarios (normal separation of duties)
    -- Examples:
    --   - Tech A performed, Receptionist closed
    --   - Tech A performed, Supervisor closed (SUPERVISOR DID NOT PERFORM)
    --   - Tech A + B performed, Tech A closed (peer approval by Tech B)
    ELSE
      v_required_level := 'technician';
      v_reason := 'Standard peer approval by technician(s)';
      NEW.requires_higher_approval := false;
    END IF;

    -- Store the calculated values
    NEW.approval_required_level := v_required_level;
    NEW.approval_reason := v_reason;
    NEW.performed_and_closed_by_same_person := v_performed_and_closed;

  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 2: FIX ALL EXISTING PENDING TICKETS
-- ============================================================================

-- This uses a simple UPDATE with subqueries instead of a loop
-- Much faster and cleaner

-- First, create a temp table with correct routing for each ticket
CREATE TEMP TABLE IF NOT EXISTS temp_approval_routing AS
SELECT
  st.id as ticket_id,
  CASE
    -- Get closer's roles
    WHEN (
      -- CASE 1: Supervisor performed and closed alone
      COALESCE(st.closed_by_roles @> '["Supervisor"]'::jsonb, false)
      AND (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = st.id) = 1
      AND st.closed_by IN (SELECT employee_id FROM ticket_items WHERE sale_ticket_id = st.id)
    ) THEN 'manager'

    WHEN (
      -- CASE 2: Receptionist with service role performed and closed alone
      COALESCE(st.closed_by_roles @> '["Receptionist"]'::jsonb, false)
      AND (
        COALESCE(st.closed_by_roles @> '["Technician"]'::jsonb, false)
        OR COALESCE(st.closed_by_roles @> '["Spa Expert"]'::jsonb, false)
      )
      AND (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = st.id) = 1
      AND st.closed_by IN (SELECT employee_id FROM ticket_items WHERE sale_ticket_id = st.id)
    ) THEN 'supervisor'

    WHEN (
      -- CASE 3: Dual-role Tech+Receptionist performed and closed alone
      COALESCE(st.closed_by_roles @> '["Technician"]'::jsonb, false)
      AND COALESCE(st.closed_by_roles @> '["Receptionist"]'::jsonb, false)
      AND (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = st.id) = 1
      AND st.closed_by IN (SELECT employee_id FROM ticket_items WHERE sale_ticket_id = st.id)
    ) THEN 'manager'

    -- CASE 4: Everything else
    ELSE 'technician'
  END as correct_level,

  CASE
    WHEN (
      COALESCE(st.closed_by_roles @> '["Supervisor"]'::jsonb, false)
      AND (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = st.id) = 1
      AND st.closed_by IN (SELECT employee_id FROM ticket_items WHERE sale_ticket_id = st.id)
    ) THEN 'Supervisor performed and closed ticket - requires Manager approval'

    WHEN (
      COALESCE(st.closed_by_roles @> '["Receptionist"]'::jsonb, false)
      AND (
        COALESCE(st.closed_by_roles @> '["Technician"]'::jsonb, false)
        OR COALESCE(st.closed_by_roles @> '["Spa Expert"]'::jsonb, false)
      )
      AND (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = st.id) = 1
      AND st.closed_by IN (SELECT employee_id FROM ticket_items WHERE sale_ticket_id = st.id)
    ) THEN 'Receptionist performed and closed ticket - requires Supervisor approval'

    WHEN (
      COALESCE(st.closed_by_roles @> '["Technician"]'::jsonb, false)
      AND COALESCE(st.closed_by_roles @> '["Receptionist"]'::jsonb, false)
      AND (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = st.id) = 1
      AND st.closed_by IN (SELECT employee_id FROM ticket_items WHERE sale_ticket_id = st.id)
    ) THEN 'Dual-role employee performed and closed ticket - requires Manager approval'

    ELSE 'Standard peer approval by technician(s)'
  END as correct_reason,

  -- Check if performed and closed by same person
  (
    (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = st.id) = 1
    AND st.closed_by IN (SELECT employee_id FROM ticket_items WHERE sale_ticket_id = st.id)
  ) as correct_performed_and_closed

FROM sale_tickets st
WHERE st.approval_status = 'pending_approval'
  AND st.closed_at IS NOT NULL;

-- Now update all tickets at once
UPDATE sale_tickets st
SET
  approval_required_level = tar.correct_level,
  approval_reason = tar.correct_reason,
  performed_and_closed_by_same_person = tar.correct_performed_and_closed,
  requires_higher_approval = (tar.correct_level != 'technician')
FROM temp_approval_routing tar
WHERE st.id = tar.ticket_id
  AND (
    st.approval_required_level IS DISTINCT FROM tar.correct_level
    OR st.approval_reason IS DISTINCT FROM tar.correct_reason
    OR st.performed_and_closed_by_same_person IS DISTINCT FROM tar.correct_performed_and_closed
  );

-- Drop temp table
DROP TABLE IF EXISTS temp_approval_routing;

-- ============================================================================
-- STEP 3: ENSURE APPROVAL FUNCTIONS ARE SIMPLE AND CORRECT
-- ============================================================================

-- Technician approval function - shows tickets where they worked and level is 'technician'
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
    AND st.approval_required_level = 'technician'  -- Simple: trust the data
    AND ti.employee_id = p_employee_id  -- Worked on this ticket
    AND st.closed_by != p_employee_id  -- Didn't close it
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- Management approval function - shows tickets requiring manager-level approval
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
    AND st.approval_required_level = 'manager'  -- Simple: trust the data
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

COMMENT ON MIGRATION IS 'Final fix: Corrects trigger logic, fixes all existing tickets, simplifies approval functions to trust the data';
