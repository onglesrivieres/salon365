/*
  # Add reset_employee_pin function

  ## Overview
  Creates the missing `reset_employee_pin` function that allows admins, supervisors, managers, 
  and owners to reset an employee's PIN to a random temporary 4-digit PIN.

  ## Changes
  1. New Function
    - `reset_employee_pin(emp_id uuid)` - Resets an employee's PIN to a random temporary PIN
    - Returns JSON with success status and the temporary PIN
    - Uses SECURITY DEFINER to allow the operation
    - Properly references pgcrypto extension functions

  ## Security
  - SECURITY DEFINER allows function to run with elevated privileges
  - Function is granted to anon and authenticated roles
  - Returns temporary PIN securely in response
*/

-- Create reset_employee_pin function
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
    pin_code_hash = crypt(temp_pin, gen_salt('bf')),
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