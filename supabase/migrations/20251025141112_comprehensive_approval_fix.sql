/*
  # Comprehensive Approval Logic Fix

  ## Problem Summary
  Admin/Manager users are seeing tickets in their pending approvals that they shouldn't see.
  Specifically: Tickets where a Supervisor closed the ticket but didn't perform the service.

  ## Root Cause
  The initial implementation incorrectly escalated ALL tickets closed by Supervisors to
  manager-level approval, regardless of whether the Supervisor performed the service.

  ## Correct Logic
  Only escalate to higher approval when there's a conflict of interest:
  - Same person performs AND closes → Higher approval needed
  - Different people perform vs close → Normal peer approval

  ## This Migration
  1. Ensures trigger logic is correct (idempotent - safe to run multiple times)
  2. Fixes ALL existing tickets with wrong approval_required_level
  3. Adds diagnostic query to verify the fix worked

  ## Testing After Migration
  Run this query to verify:
  SELECT
    ticket_no,
    approval_required_level,
    approval_reason,
    performed_and_closed_by_same_person,
    closed_by_roles,
    (SELECT COUNT(*) FROM ticket_items WHERE sale_ticket_id = sale_tickets.id) as item_count,
    (SELECT COUNT(DISTINCT employee_id) FROM ticket_items WHERE sale_ticket_id = sale_tickets.id) as performer_count
  FROM sale_tickets
  WHERE approval_status = 'pending_approval'
  ORDER BY ticket_date DESC;
*/

-- STEP 1: Recreate the trigger function with correct logic
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
  -- Only process when ticket is being closed
  IF NEW.closed_at IS NOT NULL AND (OLD.closed_at IS NULL OR OLD.closed_at IS DISTINCT FROM NEW.closed_at) THEN

    -- Set basic approval fields
    NEW.approval_status := 'pending_approval';
    NEW.approval_deadline := NEW.closed_at + INTERVAL '48 hours';

    -- Get closer's roles
    v_closer_roles := COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(NEW.closed_by_roles)),
      ARRAY[]::text[]
    );

    -- Check closer's roles
    v_closer_is_receptionist := 'Receptionist' = ANY(v_closer_roles);
    v_closer_is_supervisor := 'Supervisor' = ANY(v_closer_roles);
    v_closer_is_technician := 'Technician' = ANY(v_closer_roles);
    v_closer_is_spa_expert := 'Spa Expert' = ANY(v_closer_roles);

    -- Get list of unique performers on this ticket
    SELECT
      ARRAY_AGG(DISTINCT employee_id),
      COUNT(DISTINCT employee_id)
    INTO v_performers, v_performer_count
    FROM ticket_items
    WHERE sale_ticket_id = NEW.id;

    -- Check if closer is one of the performers
    v_closer_is_performer := NEW.closed_by = ANY(v_performers);

    -- Check if this is a single-person ticket (one person did everything)
    v_performed_and_closed := (v_performer_count = 1 AND v_closer_is_performer);

    /*
      APPROVAL ROUTING LOGIC
      ======================
      The key principle: Only escalate approval when the same person/entity has
      complete control over both service delivery AND ticket finalization.

      This prevents conflicts of interest while maintaining efficient peer approval.
    */

    -- CASE 1: Supervisor performed AND closed (single person control)
    IF v_closer_is_supervisor AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Supervisor performed service and closed ticket themselves - requires Manager/Admin approval';
      NEW.requires_higher_approval := true;

    -- CASE 2: Receptionist with service capabilities performed AND closed
    ELSIF v_closer_is_receptionist AND v_performed_and_closed AND
          (v_closer_is_technician OR v_closer_is_spa_expert) THEN
      v_required_level := 'supervisor';
      v_reason := 'Receptionist performed service and closed ticket themselves - requires Supervisor approval';
      NEW.requires_higher_approval := true;

    -- CASE 3: Dual-role employee (Tech + Receptionist) performed AND closed
    ELSIF v_closer_is_technician AND v_closer_is_receptionist AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Employee with both Technician and Receptionist roles performed and closed ticket - requires Manager/Admin approval';
      NEW.requires_higher_approval := true;

    -- CASE 4: Normal scenario - separation of duties exists
    -- Examples:
    --   - Technician A performs, Receptionist closes
    --   - Technician A performs, Supervisor closes
    --   - Technician A + B perform, Technician A closes (peer approval by B)
    ELSE
      v_required_level := 'technician';
      v_reason := 'Standard technician peer approval';
      NEW.requires_higher_approval := false;
    END IF;

    -- Set the approval metadata
    NEW.approval_required_level := v_required_level;
    NEW.approval_reason := v_reason;
    NEW.performed_and_closed_by_same_person := v_performed_and_closed;

  END IF;

  RETURN NEW;
END;
$$;

-- STEP 2: Fix ALL existing pending approval tickets
-- This is comprehensive and handles all edge cases

-- First, fix tickets where Supervisor closed but didn't perform
UPDATE sale_tickets
SET
  approval_required_level = 'technician',
  approval_reason = 'Standard technician peer approval',
  requires_higher_approval = false,
  performed_and_closed_by_same_person = false
WHERE approval_status = 'pending_approval'
  AND approval_required_level = 'manager'
  AND closed_by_roles @> '["Supervisor"]'::jsonb
  AND (
    -- Closer is not in the list of performers
    closed_by NOT IN (
      SELECT DISTINCT ti.employee_id
      FROM ticket_items ti
      WHERE ti.sale_ticket_id = sale_tickets.id
    )
    -- OR there are multiple performers (not single-person control)
    OR (
      SELECT COUNT(DISTINCT ti.employee_id)
      FROM ticket_items ti
      WHERE ti.sale_ticket_id = sale_tickets.id
    ) > 1
  );

-- Second, fix tickets where dual-role employee closed but didn't perform
UPDATE sale_tickets
SET
  approval_required_level = 'technician',
  approval_reason = 'Standard technician peer approval',
  requires_higher_approval = false,
  performed_and_closed_by_same_person = false
WHERE approval_status = 'pending_approval'
  AND approval_required_level = 'manager'
  AND closed_by_roles @> '["Technician"]'::jsonb
  AND closed_by_roles @> '["Receptionist"]'::jsonb
  AND (
    -- Closer is not in the list of performers
    closed_by NOT IN (
      SELECT DISTINCT ti.employee_id
      FROM ticket_items ti
      WHERE ti.sale_ticket_id = sale_tickets.id
    )
    -- OR there are multiple performers
    OR (
      SELECT COUNT(DISTINCT ti.employee_id)
      FROM ticket_items ti
      WHERE ti.sale_ticket_id = sale_tickets.id
    ) > 1
  );

-- Third, fix tickets where Receptionist (with service caps) closed but didn't perform
UPDATE sale_tickets
SET
  approval_required_level = 'technician',
  approval_reason = 'Standard technician peer approval',
  requires_higher_approval = false,
  performed_and_closed_by_same_person = false
WHERE approval_status = 'pending_approval'
  AND approval_required_level IN ('supervisor', 'manager')
  AND closed_by_roles @> '["Receptionist"]'::jsonb
  AND (
    closed_by_roles @> '["Technician"]'::jsonb
    OR closed_by_roles @> '["Spa Expert"]'::jsonb
  )
  AND (
    -- Closer is not in the list of performers
    closed_by NOT IN (
      SELECT DISTINCT ti.employee_id
      FROM ticket_items ti
      WHERE ti.sale_ticket_id = sale_tickets.id
    )
    -- OR there are multiple performers
    OR (
      SELECT COUNT(DISTINCT ti.employee_id)
      FROM ticket_items ti
      WHERE ti.sale_ticket_id = sale_tickets.id
    ) > 1
  );

-- STEP 3: Create a diagnostic function to check approval routing
CREATE OR REPLACE FUNCTION check_approval_routing()
RETURNS TABLE (
  issue_type text,
  ticket_count bigint,
  example_ticket_ids text[]
)
LANGUAGE sql
STABLE
AS $$
  -- Check 1: Supervisor closed but didn't perform - should be 'technician' level
  SELECT
    'Supervisor closed but did not perform (should be technician level)' as issue_type,
    COUNT(*) as ticket_count,
    ARRAY_AGG(id::text) as example_ticket_ids
  FROM sale_tickets
  WHERE approval_status = 'pending_approval'
    AND approval_required_level = 'manager'
    AND closed_by_roles @> '["Supervisor"]'::jsonb
    AND closed_by NOT IN (
      SELECT DISTINCT ti.employee_id
      FROM ticket_items ti
      WHERE ti.sale_ticket_id = sale_tickets.id
    )

  UNION ALL

  -- Check 2: Multiple performers, closer is one of them - should be 'technician' level
  SELECT
    'Multiple performers, one closed (should be technician level)' as issue_type,
    COUNT(*) as ticket_count,
    ARRAY_AGG(id::text) as example_ticket_ids
  FROM sale_tickets
  WHERE approval_status = 'pending_approval'
    AND approval_required_level IN ('supervisor', 'manager')
    AND (
      SELECT COUNT(DISTINCT ti.employee_id)
      FROM ticket_items ti
      WHERE ti.sale_ticket_id = sale_tickets.id
    ) > 1

  UNION ALL

  -- Check 3: Correctly routed tickets (for verification)
  SELECT
    'Correctly routed to technician level' as issue_type,
    COUNT(*) as ticket_count,
    ARRAY_AGG(id::text) as example_ticket_ids
  FROM sale_tickets
  WHERE approval_status = 'pending_approval'
    AND approval_required_level = 'technician';
$$;

-- Run diagnostic (results will show in migration logs if there are issues)
-- Comment out if you don't want diagnostic output during migration
-- SELECT * FROM check_approval_routing();
