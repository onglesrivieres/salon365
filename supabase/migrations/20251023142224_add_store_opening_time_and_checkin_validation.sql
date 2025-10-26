/*
  # Add Store Opening Time and Check-in Validation

  1. Changes to `stores` table
    - Add `opening_time` column (time without time zone) - Default 10:00 AM
    - Store's opening time used for check-in window validation

  2. New Functions
    - `can_checkin_now` - Validates if technician can check in (15 min before opening)
    - `is_technician_checked_in_today` - Checks if technician has active check-in for today
    - `join_ready_queue_with_checkin` - New queue join with check-in validation

  3. Security
    - Functions use SECURITY DEFINER for database access
    - Check-in validation prevents queue access without attendance record
*/

-- Add opening_time to stores table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stores' AND column_name = 'opening_time'
  ) THEN
    ALTER TABLE stores ADD COLUMN opening_time time DEFAULT '10:00:00'::time;
  END IF;
END $$;

-- Function to check if technician can check in (15 minutes before opening)
CREATE OR REPLACE FUNCTION can_checkin_now(p_store_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_opening_time time;
  v_current_time time;
  v_check_in_window_start time;
BEGIN
  -- Get store opening time
  SELECT opening_time INTO v_opening_time
  FROM stores
  WHERE id = p_store_id;

  IF v_opening_time IS NULL THEN
    RETURN true; -- Allow if no opening time set
  END IF;

  -- Get current time in store's timezone (Eastern Time)
  v_current_time := (NOW() AT TIME ZONE 'America/New_York')::time;

  -- Calculate check-in window start (15 minutes before opening)
  v_check_in_window_start := v_opening_time - interval '15 minutes';

  -- Allow check-in if current time is within window
  RETURN v_current_time >= v_check_in_window_start;
END;
$$;

-- Function to check if technician is checked in today
CREATE OR REPLACE FUNCTION is_technician_checked_in_today(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_checked_in boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM attendance_records
    WHERE employee_id = p_employee_id
      AND store_id = p_store_id
      AND work_date = CURRENT_DATE
      AND status = 'checked_in'
      AND check_in_time IS NOT NULL
      AND check_out_time IS NULL
  ) INTO v_checked_in;

  RETURN v_checked_in;
END;
$$;

-- New function with check-in validation that returns jsonb
CREATE OR REPLACE FUNCTION join_ready_queue_with_checkin(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_is_checked_in boolean;
  v_existing_entry record;
  v_queue_id uuid;
BEGIN
  -- Check if technician is checked in today
  v_is_checked_in := is_technician_checked_in_today(p_employee_id, p_store_id);

  IF NOT v_is_checked_in THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'CHECK_IN_REQUIRED',
      'message', 'You must check in before joining the ready queue'
    );
  END IF;

  -- Check if already in queue
  SELECT * INTO v_existing_entry
  FROM technician_ready_queue
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id
    AND status IN ('ready', 'busy');

  IF v_existing_entry.id IS NOT NULL THEN
    -- Complete any open tickets first
    UPDATE sale_tickets
    SET completed_at = NOW(),
        completed_by = p_employee_id
    WHERE id = v_existing_entry.current_open_ticket_id
      AND completed_at IS NULL;

    -- Update queue entry to ready
    UPDATE technician_ready_queue
    SET status = 'ready',
        current_open_ticket_id = NULL,
        ready_at = NOW(),
        updated_at = NOW()
    WHERE id = v_existing_entry.id;

    RETURN jsonb_build_object(
      'success', true,
      'action', 'updated',
      'queue_id', v_existing_entry.id
    );
  ELSE
    -- Insert new queue entry
    INSERT INTO technician_ready_queue (employee_id, store_id, status, ready_at)
    VALUES (p_employee_id, p_store_id, 'ready', NOW())
    RETURNING id INTO v_queue_id;

    RETURN jsonb_build_object(
      'success', true,
      'action', 'joined',
      'queue_id', v_queue_id
    );
  END IF;
END;
$$;