/*
  # Fix Application State for Null Employee ID

  ## Overview
  Updates application_state table and functions to properly handle null employee_id for global state like version hashes.

  ## Changes
  - Make employee_id nullable in application_state table
  - Update unique constraint to include device_id
  - Update functions to handle null employee_id
*/

-- Drop existing constraint if any
ALTER TABLE application_state DROP CONSTRAINT IF EXISTS unique_employee_state_key;

-- Add unique constraint on (employee_id, state_key, device_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'unique_employee_state_device_key'
  ) THEN
    ALTER TABLE application_state 
    ADD CONSTRAINT unique_employee_state_device_key 
    UNIQUE (employee_id, state_key, device_id);
  END IF;
END $$;

-- Update get_application_state function to handle null employee_id
CREATE OR REPLACE FUNCTION get_application_state(
  emp_id uuid,
  state_key text,
  device_id text DEFAULT ''
)
RETURNS text AS $$
DECLARE
  v_state_value text;
BEGIN
  SELECT state_value INTO v_state_value
  FROM application_state
  WHERE (employee_id = emp_id OR (employee_id IS NULL AND emp_id IS NULL))
    AND application_state.state_key = get_application_state.state_key
    AND application_state.device_id = get_application_state.device_id;
  
  RETURN v_state_value;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update set_application_state function to handle null employee_id
CREATE OR REPLACE FUNCTION set_application_state(
  emp_id uuid,
  state_key text,
  state_value text,
  device_id text DEFAULT ''
)
RETURNS boolean AS $$
BEGIN
  -- Use upsert with the unique constraint
  INSERT INTO application_state (employee_id, state_key, state_value, device_id, updated_at)
  VALUES (emp_id, state_key, state_value, device_id, now())
  ON CONFLICT (employee_id, state_key, device_id)
  DO UPDATE SET
    state_value = EXCLUDED.state_value,
    updated_at = now();
  
  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    -- If there's any error, try to update existing record
    UPDATE application_state
    SET state_value = set_application_state.state_value, updated_at = now()
    WHERE (employee_id = emp_id OR (employee_id IS NULL AND emp_id IS NULL))
      AND application_state.state_key = set_application_state.state_key
      AND application_state.device_id = set_application_state.device_id;
      
    IF NOT FOUND THEN
      -- Record doesn't exist, something went wrong
      RETURN false;
    END IF;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;