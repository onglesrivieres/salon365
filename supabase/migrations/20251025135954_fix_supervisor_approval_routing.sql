/*
  # Fix Supervisor Approval Routing

  ## Problem
  The current logic sends ALL tickets closed by Supervisors to management approval,
  even when the Supervisor didn't perform the service. This is incorrect.

  ## Correct Logic
  1. **Supervisor performs service AND closes** → Manager/Admin approval (conflict of interest)
  2. **Supervisor closes but didn't perform** → Technician who performed approves (normal peer approval)
  3. **Receptionist performs AND closes** → Supervisor approval
  4. **Dual-role (Tech+Receptionist) closes** → Manager approval

  ## Changes
  - Update set_approval_deadline trigger to only require manager approval when:
    - Supervisor performed AND closed (v_performed_and_closed = true)
    - NOT when Supervisor only closed (v_performed_and_closed = false)
  - Remove CASE 3 which was incorrectly escalating all supervisor closures
  - Keep only the cases where self-approval is a conflict of interest

  ## Business Rules
  The key principle: Only escalate approval when someone has complete control over both:
  1. Performing the service (quality and work done)
  2. Closing the ticket (finalizing prices and billing)

  If different people handle these two actions, normal peer approval applies.
*/

-- Update set_approval_deadline trigger with corrected logic
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
  v_performer_roles text[];
  v_performers_are_supervisor boolean;
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

    -- Check if any performers are Supervisors
    SELECT bool_or('Supervisor' = ANY(e.role))
    INTO v_performers_are_supervisor
    FROM employees e
    WHERE e.id = ANY(v_performers);

    -- Determine approval level required based on who performed and who closed
    -- KEY PRINCIPLE: Only escalate when same person/role has complete control

    -- CASE 1: Supervisor performed service and closed it themselves
    -- This is a conflict of interest - they control both service quality and billing
    IF v_closer_is_supervisor AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Supervisor performed service and closed ticket themselves - requires Manager/Admin approval';
      NEW.requires_higher_approval := true;

    -- CASE 2: Receptionist with tech capabilities performed service and closed it themselves
    -- Receptionist shouldn't approve their own technical work
    ELSIF v_closer_is_receptionist AND v_performed_and_closed AND
          (v_closer_is_technician OR v_closer_is_spa_expert) THEN
      v_required_level := 'supervisor';
      v_reason := 'Receptionist performed service and closed ticket themselves - requires Supervisor approval';
      NEW.requires_higher_approval := true;

    -- CASE 3: Dual-role (Technician + Receptionist) closer performed and closed
    -- Same as above - complete control over ticket lifecycle
    ELSIF v_closer_is_technician AND v_closer_is_receptionist AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Employee with both Technician and Receptionist roles performed and closed ticket - requires Manager/Admin approval';
      NEW.requires_higher_approval := true;

    -- CASE 4: Normal scenario - separation of duties exists
    -- Someone performed the service, someone else (or group approval) closes it
    -- Standard peer approval by technicians who worked on it
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

-- Note: The trigger already exists, no need to recreate it
-- It will automatically use the updated function

-- Update any existing pending approval tickets that were incorrectly classified
-- This fixes tickets where Supervisor closed but didn't perform
UPDATE sale_tickets
SET
  approval_required_level = 'technician',
  approval_reason = 'Standard technician peer approval',
  requires_higher_approval = false
WHERE approval_status = 'pending_approval'
  AND approval_required_level = 'manager'
  AND closed_by_roles @> '["Supervisor"]'::jsonb
  AND performed_and_closed_by_same_person = false
  AND closed_by NOT IN (
    SELECT DISTINCT ti.employee_id
    FROM ticket_items ti
    WHERE ti.sale_ticket_id = sale_tickets.id
  );
