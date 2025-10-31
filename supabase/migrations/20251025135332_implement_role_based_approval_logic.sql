/*
  # Implement Role-Based Approval Logic

  ## Overview
  Implements comprehensive approval logic based on who performed the service vs who closed the ticket:

  ### Approval Rules:
  1. **Technician/Spa Expert performs service:**
     - If someone else closes → They approve (peer approval)
     - If they close it themselves → Cannot approve their own work

  2. **Receptionist performs service and closes it themselves:**
     - Requires Supervisor approval (receptionist cannot approve their own service)

  3. **Supervisor performs service and closes it themselves:**
     - Requires Manager/Admin approval (supervisor cannot approve their own service)

  4. **General Rules:**
     - Closer cannot approve tickets they closed
     - Workers cannot approve tickets where they were the only worker AND closer
     - Separation of duties enforced at all levels

  ## New Columns
  - `approval_required_level` (text) - The minimum role level required to approve
      Values: 'technician', 'supervisor', 'manager'
  - `approval_reason` (text) - Human-readable reason for the approval requirement
  - `performed_and_closed_by_same_person` (boolean) - Flag when same person did service and closed

  ## Changes
  1. Add new tracking columns to sale_tickets
  2. Update set_approval_deadline trigger to analyze performer vs closer
  3. Update approve_ticket function with hierarchical approval rules
  4. Update pending approval functions to route tickets correctly
  5. Create new function for supervisor-level approvals

  ## Security
  - Enforces separation of duties at all role levels
  - Prevents conflicts of interest
  - Maintains audit trail of approval requirements
*/

-- Add new columns for approval metadata
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'approval_required_level'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN approval_required_level text DEFAULT 'technician';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'approval_reason'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN approval_reason text DEFAULT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'performed_and_closed_by_same_person'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN performed_and_closed_by_same_person boolean DEFAULT false;
  END IF;
END $$;

-- Create index for performance on approval_required_level
CREATE INDEX IF NOT EXISTS idx_sale_tickets_approval_required_level
  ON sale_tickets(approval_required_level);

-- Update set_approval_deadline trigger to determine approval requirements
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

    -- Determine approval level required based on who performed and who closed

    -- CASE 1: Supervisor performed service and closed it themselves
    IF v_closer_is_supervisor AND v_performed_and_closed THEN
      v_required_level := 'manager';
      v_reason := 'Supervisor performed service and closed ticket themselves - requires Manager/Admin approval';
      NEW.requires_higher_approval := true;

    -- CASE 2: Receptionist performed service and closed it themselves
    ELSIF v_closer_is_receptionist AND v_performed_and_closed AND
          (v_closer_is_technician OR v_closer_is_spa_expert) THEN
      v_required_level := 'supervisor';
      v_reason := 'Receptionist performed service and closed ticket themselves - requires Supervisor approval';
      NEW.requires_higher_approval := true;

    -- CASE 3: Supervisor closed ticket (even if they didn't perform service)
    ELSIF v_closer_is_supervisor THEN
      v_required_level := 'manager';
      v_reason := 'Ticket closed by Supervisor - requires Manager/Admin approval';
      NEW.requires_higher_approval := true;

    -- CASE 4: Dual-role (Technician + Receptionist) closer
    ELSIF v_closer_is_technician AND v_closer_is_receptionist THEN
      v_required_level := 'manager';
      v_reason := 'Ticket closed by employee with both Technician and Receptionist roles - requires Manager/Admin approval';
      NEW.requires_higher_approval := true;

    -- CASE 5: Normal technician approval (someone else closes)
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

-- Ensure trigger exists
DROP TRIGGER IF EXISTS trigger_set_approval_deadline ON sale_tickets;
CREATE TRIGGER trigger_set_approval_deadline
  BEFORE UPDATE ON sale_tickets
  FOR EACH ROW
  EXECUTE FUNCTION set_approval_deadline();

-- Update approve_ticket function with hierarchical approval rules
CREATE OR REPLACE FUNCTION approve_ticket(
  p_ticket_id uuid,
  p_employee_id uuid
)
RETURNS json
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ticket sale_tickets;
  v_approver_roles text[];
  v_can_approve boolean;
  v_is_technician boolean;
  v_is_spa_expert boolean;
  v_is_supervisor boolean;
  v_is_manager boolean;
  v_is_admin boolean;
  v_worked_on_ticket boolean;
BEGIN
  -- Get the ticket
  SELECT * INTO v_ticket FROM sale_tickets WHERE id = p_ticket_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'Ticket not found');
  END IF;

  -- Check if ticket is in pending_approval status
  IF v_ticket.approval_status != 'pending_approval' THEN
    RETURN json_build_object('success', false, 'message', 'Ticket is not pending approval');
  END IF;

  -- Check if approver is different from closer
  IF v_ticket.closed_by = p_employee_id THEN
    RETURN json_build_object('success', false, 'message', 'You cannot approve a ticket you closed');
  END IF;

  -- Get approver's roles
  SELECT role INTO v_approver_roles FROM employees WHERE id = p_employee_id;

  IF v_approver_roles IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'Approver not found');
  END IF;

  -- Check approver's role levels
  v_is_technician := 'Technician' = ANY(v_approver_roles);
  v_is_spa_expert := 'Spa Expert' = ANY(v_approver_roles);
  v_is_supervisor := 'Supervisor' = ANY(v_approver_roles);
  v_is_manager := 'Manager' = ANY(v_approver_roles);
  v_is_admin := 'Owner' = ANY(v_approver_roles);

  -- Check if approver worked on this ticket
  v_worked_on_ticket := EXISTS (
    SELECT 1 FROM ticket_items
    WHERE sale_ticket_id = p_ticket_id AND employee_id = p_employee_id
  );

  -- Apply hierarchical approval rules based on required level
  CASE v_ticket.approval_required_level

    -- Manager/Admin level required
    WHEN 'manager' THEN
      IF NOT (v_is_manager OR v_is_admin) THEN
        RETURN json_build_object(
          'success', false,
          'message', format('This ticket requires Manager or Admin approval. Reason: %s', v_ticket.approval_reason)
        );
      END IF;
      v_can_approve := true;

    -- Supervisor level required
    WHEN 'supervisor' THEN
      IF NOT (v_is_supervisor OR v_is_manager OR v_is_admin) THEN
        RETURN json_build_object(
          'success', false,
          'message', format('This ticket requires Supervisor or higher approval. Reason: %s', v_ticket.approval_reason)
        );
      END IF;
      v_can_approve := true;

    -- Technician level (peer approval)
    WHEN 'technician' THEN
      -- For technician-level approval, must have worked on the ticket
      IF NOT v_worked_on_ticket THEN
        -- Unless they're management who can approve anything
        IF NOT (v_is_supervisor OR v_is_manager OR v_is_admin) THEN
          RETURN json_build_object(
            'success', false,
            'message', 'You must have worked on this ticket to approve it, or be a Supervisor or higher'
          );
        END IF;
      END IF;

      -- Technician or Spa Expert can approve if they worked on it
      IF NOT (v_is_technician OR v_is_spa_expert OR v_is_supervisor OR v_is_manager OR v_is_admin) THEN
        RETURN json_build_object(
          'success', false,
          'message', 'You do not have permission to approve tickets'
        );
      END IF;

      v_can_approve := true;

    ELSE
      RETURN json_build_object('success', false, 'message', 'Invalid approval level configuration');
  END CASE;

  -- Additional check: If performer and closer are the same person, they cannot approve
  IF v_ticket.performed_and_closed_by_same_person AND v_worked_on_ticket THEN
    -- Management can still approve
    IF NOT (v_is_manager OR v_is_admin) THEN
      RETURN json_build_object(
        'success', false,
        'message', 'You cannot approve this ticket because you both performed the service and closed it'
      );
    END IF;
  END IF;

  -- Approve the ticket
  UPDATE sale_tickets
  SET
    approval_status = 'approved',
    approved_at = NOW(),
    approved_by = p_employee_id,
    updated_at = NOW()
  WHERE id = p_ticket_id;

  RETURN json_build_object('success', true, 'message', 'Ticket approved successfully');
END;
$$;

-- Update get_pending_approvals_for_technician to only show technician-level approvals
DROP FUNCTION IF EXISTS get_pending_approvals_for_technician(uuid, uuid);

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
DECLARE
  v_employee_roles text[];
BEGIN
  -- Get the employee's roles
  SELECT role INTO v_employee_roles FROM employees WHERE id = p_employee_id;

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
    -- Only show tickets requiring technician-level approval
    AND st.approval_required_level = 'technician'
    -- Must have worked on this ticket
    AND ti.employee_id = p_employee_id
    -- Cannot approve tickets they closed
    AND st.closed_by != p_employee_id
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- Create function for supervisor-level approvals
CREATE OR REPLACE FUNCTION get_pending_approvals_for_supervisor(
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
  approval_reason text,
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
    EXTRACT(EPOCH FROM (st.approval_deadline - NOW())) / 3600 as hours_remaining,
    STRING_AGG(DISTINCT s.name, ', ') as service_name,
    SUM(ti.tip_customer) as tip_customer,
    SUM(ti.tip_receptionist) as tip_receptionist,
    st.payment_method,
    st.approval_reason,
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
    -- Only show tickets requiring supervisor-level approval
    AND st.approval_required_level = 'supervisor'
    -- Supervisor cannot approve tickets they closed
    AND st.closed_by != p_employee_id
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- Update get_pending_approvals_for_management for manager-level approvals
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
    -- Only show tickets requiring manager-level approval
    AND st.approval_required_level = 'manager'
  GROUP BY st.id, e.display_name
  ORDER BY st.approval_deadline ASC;
END;
$$;

-- Backfill existing tickets with default values
UPDATE sale_tickets
SET
  approval_required_level = CASE
    WHEN requires_higher_approval = true THEN 'manager'
    ELSE 'technician'
  END,
  approval_reason = CASE
    WHEN requires_higher_approval = true THEN 'Legacy ticket - requires higher approval'
    ELSE 'Legacy ticket - standard approval'
  END,
  performed_and_closed_by_same_person = false
WHERE approval_status IS NOT NULL
  AND approval_required_level IS NULL;
