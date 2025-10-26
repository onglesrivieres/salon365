/*
  # Fix PIN Functions Schema References

  ## Overview
  Updates the set_employee_pin function to properly reference the pgcrypto
  extension functions in the extensions schema.

  ## Changes
  - Update set_employee_pin to use extensions.crypt and extensions.gen_salt
  - Ensures proper schema qualification for pgcrypto functions

  ## Security
  - Maintains SECURITY DEFINER for controlled access
  - Validates PIN format (4 digits only)
*/

-- Drop and recreate the function with correct schema references
DROP FUNCTION IF EXISTS set_employee_pin(uuid, text);
CREATE OR REPLACE FUNCTION public.set_employee_pin(emp_id uuid, new_pin text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  -- Validate PIN is exactly 4 digits
  IF new_pin !~ '^\d{4}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'PIN must be exactly 4 digits');
  END IF;

  -- Update employee with new PIN
  UPDATE employees
  SET 
    pin_code_hash = extensions.crypt(new_pin, extensions.gen_salt('bf')),
    pin_temp = NULL,
    last_pin_change = now(),
    updated_at = now()
  WHERE id = emp_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Employee not found');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Also fix verify_employee_pin function
DROP FUNCTION IF EXISTS verify_employee_pin(uuid, text);
CREATE OR REPLACE FUNCTION public.verify_employee_pin(emp_id uuid, pin_code text)
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
