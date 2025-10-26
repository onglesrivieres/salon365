/*
  # Add Service-Level Completion Tracking

  ## Overview
  Adds completion tracking at the service (ticket_item) level instead of just the ticket level.
  This allows individual services to be marked as completed while keeping the ticket open.

  ## Changes
  
  1. New Columns
    - `ticket_items.completed_at` (timestamptz) - When the service was completed
    - `ticket_items.completed_by` (uuid) - Which employee completed the service
    - `ticket_items.started_at` (timestamptz) - When service work began (for timer tracking)
  
  2. Updated Functions
    - `join_ready_queue_with_checkin` - Now marks individual services as completed, not entire tickets
    - New helper function to check if all ticket services are completed
  
  ## Business Logic
  - When a technician clicks "Ready", only THEIR services on the ticket are marked completed
  - The ticket stays open if other technicians still have incomplete services on it
  - The ticket is automatically marked as completed when ALL services are completed
  - Receptionist can still close completed tickets normally
  
  ## Notes
  - Preserves existing ticket-level completion for backwards compatibility
  - Service completion is independent of ticket closure
  - Timer tracking via started_at enables duration calculations
*/

-- Add completion tracking columns to ticket_items
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'completed_at'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN completed_at timestamptz DEFAULT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'completed_by'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN completed_by uuid REFERENCES employees(id) DEFAULT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'started_at'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN started_at timestamptz DEFAULT NULL;
  END IF;
END $$;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_ticket_items_completed_at ON ticket_items(completed_at);
CREATE INDEX IF NOT EXISTS idx_ticket_items_started_at ON ticket_items(started_at);

-- Helper function to check if all services on a ticket are completed
CREATE OR REPLACE FUNCTION check_ticket_all_services_completed(p_ticket_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_incomplete_count int;
BEGIN
  SELECT COUNT(*)
  INTO v_incomplete_count
  FROM ticket_items
  WHERE sale_ticket_id = p_ticket_id
    AND completed_at IS NULL;
  
  RETURN v_incomplete_count = 0;
END;
$$;

-- Drop and recreate join_ready_queue_with_checkin with updated logic
DROP FUNCTION IF EXISTS join_ready_queue_with_checkin(uuid, uuid);

CREATE OR REPLACE FUNCTION join_ready_queue_with_checkin(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS json
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_attendance record;
  v_today date;
  v_all_completed boolean;
  v_ticket_id uuid;
BEGIN
  v_today := CURRENT_DATE;

  -- Check if employee is checked in
  SELECT *
  INTO v_attendance
  FROM attendance_records
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id
    AND work_date = v_today
    AND status = 'checked_in'
  ORDER BY check_in_time DESC
  LIMIT 1;

  IF v_attendance IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'CHECK_IN_REQUIRED',
      'message', 'You must check in before joining the ready queue'
    );
  END IF;

  -- Mark individual services (ticket_items) assigned to this technician as completed
  -- Do NOT close the entire ticket yet
  UPDATE ticket_items ti
  SET
    completed_at = NOW(),
    completed_by = p_employee_id,
    updated_at = NOW()
  WHERE ti.employee_id = p_employee_id
    AND ti.completed_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM sale_tickets st
      WHERE st.id = ti.sale_ticket_id
        AND st.store_id = p_store_id
        AND st.closed_at IS NULL
    );

  -- For each affected ticket, check if ALL services are now completed
  -- If so, mark the ticket as completed (but not closed)
  FOR v_ticket_id IN (
    SELECT DISTINCT ti.sale_ticket_id
    FROM ticket_items ti
    INNER JOIN sale_tickets st ON st.id = ti.sale_ticket_id
    WHERE ti.employee_id = p_employee_id
      AND st.store_id = p_store_id
      AND st.closed_at IS NULL
      AND st.completed_at IS NULL
  )
  LOOP
    v_all_completed := check_ticket_all_services_completed(v_ticket_id);
    
    IF v_all_completed THEN
      UPDATE sale_tickets
      SET
        completed_at = NOW(),
        completed_by = p_employee_id,
        updated_at = NOW()
      WHERE id = v_ticket_id
        AND completed_at IS NULL;
    END IF;
  END LOOP;

  -- Remove any existing entry for this technician in this store
  DELETE FROM technician_ready_queue
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id;

  -- Add technician to ready queue
  INSERT INTO technician_ready_queue (
    employee_id,
    store_id,
    status,
    ready_at
  ) VALUES (
    p_employee_id,
    p_store_id,
    'ready',
    NOW()
  );

  RETURN json_build_object('success', true);
END;
$$;