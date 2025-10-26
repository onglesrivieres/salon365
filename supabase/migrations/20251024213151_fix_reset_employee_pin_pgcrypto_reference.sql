/*
  # Fix reset_employee_pin function pgcrypto references

  ## Overview
  Fixes the `reset_employee_pin` function to properly reference pgcrypto extension functions
  using the `extensions.` schema prefix.

  ## Changes
  1. Updates Function
    - `reset_employee_pin(emp_id uuid)` - Fixed to use `extensions.gen_salt` and `extensions.crypt`
    - Maintains all existing functionality
    - Properly scoped to avoid schema search_path issues

  ## Security
  - Maintains SECURITY DEFINER with safe search_path
  - No changes to permissions or access control
*/

-- Drop and recreate reset_employee_pin with proper pgcrypto references
DROP FUNCTION IF EXISTS reset_employee_pin(uuid);

CREATE OR REPLACE FUNCTION reset_employee_pin(emp_id uuid)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql
AS $$
DECLARE
  temp_pin text;
BEGIN
  -- Generate random 4-digit PIN
  temp_pin := lpad(floor(random() * 10000)::text, 4, '0');

  -- Update employee with temporary PIN
  UPDATE employees
  SET 
    pin_code_hash = extensions.crypt(temp_pin, extensions.gen_salt('bf')),
    pin_temp = temp_pin,
    last_pin_change = now(),
    updated_at = now()
  WHERE id = emp_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Employee not found');
  END IF;

  RETURN jsonb_build_object('success', true, 'temp_pin', temp_pin);
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION reset_employee_pin(uuid) TO anon, authenticated;

-- Add comment
COMMENT ON FUNCTION reset_employee_pin IS 'Resets employee PIN to a random temporary PIN. Returns the temporary PIN that must be shared with the employee.';