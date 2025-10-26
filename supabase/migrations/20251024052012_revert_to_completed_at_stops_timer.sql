/*
  # Revert to Using completed_at to Stop Timer (Not closed_at)

  ## Overview
  Reverts the recent change that closed tickets when technician clicks Ready.
  Instead, we use the existing `completed_at` field to stop the timer while keeping
  the ticket open for the receptionist to finalize.

  ## Changes
  - Restores `join_ready_queue_with_checkin` to mark services as completed
  - Sets ticket `completed_at` when all services are done
  - Does NOT set `closed_at` (ticket remains open for receptionist)
  
  ## Business Logic
  1. Technician clicks "Ready" button
  2. Their services are marked as completed (ticket_items.completed_at)
  3. If all services on the ticket are complete, ticket.completed_at is set
  4. Timer stops at completed_at (frontend change handles this)
  5. Ticket stays open for receptionist to close after payment/finalization
  
  ## Benefits
  - Clear separation: technician completes work, receptionist closes ticket
  - Timer stops when work is done (completed_at)
  - Ticket remains editable until receptionist closes it
  - Maintains proper workflow and audit trail
*/

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
  -- Do NOT close the entire ticket
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
  -- If so, mark the ticket as completed (but NOT closed)
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
      -- Mark ticket as completed but keep it open
      -- Timer will stop at completed_at, but receptionist can still close it
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