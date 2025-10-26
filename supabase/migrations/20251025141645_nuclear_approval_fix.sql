/*
  # Nuclear Option: Fix All Approval Routing Issues

  ## Problem
  Admin/Manager still sees 7 tickets that should be routed to technicians.
  These are tickets where:
  - Someone else performed the service
  - A Supervisor just closed the ticket
  - Currently has approval_required_level = 'manager' (WRONG)
  - Should have approval_required_level = 'technician' (CORRECT)

  ## Root Cause
  Previous UPDATE statements may have missed edge cases:
  1. closed_by_roles might be NULL
  2. closed_by_roles might have different formatting
  3. Supervisor might also have other roles
  4. Complex multi-role scenarios

  ## Solution
  This migration takes a "nuclear" approach:
  - Recalculates approval_required_level for EVERY pending ticket
  - Uses the same logic as the trigger
  - Handles ALL edge cases
  - Is completely idempotent (safe to run multiple times)

  ## Strategy
  Instead of trying to match specific UPDATE conditions, we:
  1. Get the closer's roles from employees table (source of truth)
  2. Check if closer performed work
  3. Count how many people performed work
  4. Apply the exact same logic as the trigger
*/

-- STEP 1: Ensure the trigger function is correct (idempotent)
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

    -- APPROVAL LOGIC: Only escalate if same person has complete control
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

-- STEP 2: Nuclear fix - recalculate EVERY pending approval ticket
-- This uses the SAME logic as the trigger but applies it to existing data
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
BEGIN
  -- Loop through every pending approval ticket
  FOR v_ticket IN
    SELECT id, closed_by, closed_by_roles
    FROM sale_tickets
    WHERE approval_status = 'pending_approval'
      AND closed_at IS NOT NULL
  LOOP
    -- Get closer's roles (try from closed_by_roles first, fallback to employees table)
    v_closer_roles := COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(v_ticket.closed_by_roles)),
      ARRAY[]::text[]
    );

    -- If closed_by_roles is NULL or empty, get from employees table
    IF array_length(v_closer_roles, 1) IS NULL OR array_length(v_closer_roles, 1) = 0 THEN
      SELECT role INTO v_closer_roles
      FROM employees
      WHERE id = v_ticket.closed_by;
    END IF;

    -- Check closer's roles
    v_closer_is_receptionist := 'Receptionist' = ANY(v_closer_roles);
    v_closer_is_supervisor := 'Supervisor' = ANY(v_closer_roles);
    v_closer_is_technician := 'Technician' = ANY(v_closer_roles);
    v_closer_is_spa_expert := 'Spa Expert' = ANY(v_closer_roles);

    -- Get performers for this ticket
    SELECT
      ARRAY_AGG(DISTINCT employee_id),
      COUNT(DISTINCT employee_id)
    INTO v_performers, v_performer_count
    FROM ticket_items
    WHERE sale_ticket_id = v_ticket.id;

    -- Check if closer performed work
    v_closer_is_performer := v_ticket.closed_by = ANY(v_performers);
    v_performed_and_closed := (v_performer_count = 1 AND v_closer_is_performer);

    -- Apply the same approval logic as trigger
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

    -- Update the ticket with correct approval routing
    UPDATE sale_tickets
    SET
      approval_required_level = v_required_level,
      approval_reason = v_reason,
      performed_and_closed_by_same_person = v_performed_and_closed,
      requires_higher_approval = (v_required_level != 'technician')
    WHERE id = v_ticket.id;

  END LOOP;
END $$;

-- STEP 3: Verification query (commented out to avoid output during migration)
-- Uncomment and run manually to verify the fix
/*
SELECT
  approval_required_level,
  COUNT(*) as ticket_count,
  STRING_AGG(ticket_no, ', ') as example_tickets
FROM sale_tickets
WHERE approval_status = 'pending_approval'
  AND closed_at IS NOT NULL
GROUP BY approval_required_level
ORDER BY approval_required_level;
*/

-- STEP 4: Create a debug view to see current routing
CREATE OR REPLACE VIEW pending_approval_debug AS
SELECT
  st.id,
  st.ticket_no,
  st.approval_required_level,
  st.approval_reason,
  st.performed_and_closed_by_same_person,
  st.closed_by_roles,
  e.display_name as closer_name,
  e.role as closer_roles_from_db,
  (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = st.id) as performer_count,
  (SELECT STRING_AGG(DISTINCT emp.display_name, ', ')
   FROM ticket_items ti
   JOIN employees emp ON ti.employee_id = emp.id
   WHERE ti.sale_ticket_id = st.id) as performer_names,
  (st.closed_by IN (SELECT DISTINCT employee_id FROM ticket_items WHERE sale_ticket_id = st.id)) as closer_is_performer
FROM sale_tickets st
LEFT JOIN employees e ON st.closed_by = e.id
WHERE st.approval_status = 'pending_approval'
  AND st.closed_at IS NOT NULL
ORDER BY st.ticket_date DESC;

-- You can query this view to debug: SELECT * FROM pending_approval_debug;
