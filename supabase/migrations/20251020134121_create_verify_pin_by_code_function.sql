/*
  # Create Function to Verify PIN by Code Only

  ## Overview
  Creates a function that verifies a PIN code against all active employees
  and returns the matching employee's data. This is used for login where
  the employee ID is not known yet.

  ## New Function
  - verify_employee_pin(pin_input text)
    - Searches all active employees for matching PIN
    - Returns employee data if PIN matches
    - Used for PIN-based login

  ## Security
  - Only checks active employees
  - Returns minimal employee data needed for session
  - Uses SECURITY DEFINER for controlled access to hashed PINs
*/

-- Create function to verify PIN for login (without knowing employee ID)
CREATE OR REPLACE FUNCTION public.verify_employee_pin(pin_input text)
RETURNS TABLE (
  employee_id uuid,
  display_name text,
  role text[],
  role_permission text,
  can_reset_pin boolean,
  store_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    e.id as employee_id,
    e.display_name,
    e.role,
    e.role_permission,
    e.can_reset_pin,
    NULL::uuid as store_id
  FROM employees e
  WHERE e.status = 'Active'
    AND e.pin_code_hash IS NOT NULL
    AND e.pin_code_hash = extensions.crypt(pin_input, e.pin_code_hash)
  LIMIT 1;
END;
$$;

-- Keep the original function with different signature for other uses
CREATE OR REPLACE FUNCTION public.verify_employee_pin_by_id(emp_id uuid, pin_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_pin_hash text;
  v_employee record;
BEGIN
  -- Get employee data
  SELECT 
    id,
    display_name,
    role,
    role_permission,
    pin_code_hash,
    status
  INTO v_employee
  FROM employees
  WHERE id = emp_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Employee not found'
    );
  END IF;

  IF v_employee.status != 'Active' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Employee is not active'
    );
  END IF;

  -- Verify PIN
  IF v_employee.pin_code_hash IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No PIN set for this employee'
    );
  END IF;

  IF v_employee.pin_code_hash != extensions.crypt(pin_code, v_employee.pin_code_hash) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Invalid PIN'
    );
  END IF;

  -- Return success with employee data
  RETURN jsonb_build_object(
    'success', true,
    'employee', jsonb_build_object(
      'id', v_employee.id,
      'display_name', v_employee.display_name,
      'role', v_employee.role,
      'role_permission', v_employee.role_permission
    )
  );
END;
$$;
