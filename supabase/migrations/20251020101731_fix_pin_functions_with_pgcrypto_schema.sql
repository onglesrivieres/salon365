/*
  # Fix PIN Functions with pgcrypto Schema

  1. Updates
    - Recreate PIN management functions with explicit pgcrypto schema references
    - Ensures crypt and gen_salt functions are properly resolved
*/

-- Drop existing functions
DROP FUNCTION IF EXISTS verify_employee_pin(text);
DROP FUNCTION IF EXISTS change_employee_pin(uuid, text, text);
DROP FUNCTION IF EXISTS reset_employee_pin(uuid);

-- Recreate function to verify PIN
CREATE OR REPLACE FUNCTION verify_employee_pin(pin_input text)
RETURNS TABLE (
  employee_id uuid,
  display_name text,
  role text[],
  role_permission text,
  can_reset_pin boolean,
  store_id uuid
) 
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Validate PIN format (4 digits)
  IF pin_input !~ '^\d{4}$' THEN
    RETURN;
  END IF;

  -- Find employee with matching PIN
  RETURN QUERY
  SELECT 
    e.id,
    e.display_name,
    e.role,
    COALESCE(e.role_permission::text, 'Technician'),
    COALESCE(e.can_reset_pin, false),
    e.store_id
  FROM employees e
  WHERE 
    e.status = 'Active'
    AND e.pin_code_hash IS NOT NULL
    AND e.pin_code_hash = extensions.crypt(pin_input, e.pin_code_hash)
  LIMIT 1;
END;
$$;

-- Recreate function to change employee PIN
CREATE OR REPLACE FUNCTION change_employee_pin(
  emp_id uuid,
  old_pin text,
  new_pin text
)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
  current_hash text;
BEGIN
  -- Validate new PIN format
  IF new_pin !~ '^\d{4}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'New PIN must be exactly 4 digits');
  END IF;

  -- Check if old and new PINs are the same
  IF old_pin = new_pin THEN
    RETURN jsonb_build_object('success', false, 'error', 'New PIN must be different from old PIN');
  END IF;

  -- Get current PIN hash
  SELECT pin_code_hash INTO current_hash
  FROM employees
  WHERE id = emp_id;

  IF current_hash IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Employee not found');
  END IF;

  -- Verify old PIN
  IF current_hash != extensions.crypt(old_pin, current_hash) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Current PIN is incorrect');
  END IF;

  -- Update with new PIN
  UPDATE employees
  SET 
    pin_code_hash = extensions.crypt(new_pin, extensions.gen_salt('bf')),
    pin_temp = null,
    last_pin_change = now(),
    updated_at = now()
  WHERE id = emp_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Recreate function to reset employee PIN
CREATE OR REPLACE FUNCTION reset_employee_pin(emp_id uuid)
RETURNS jsonb
SECURITY DEFINER
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
GRANT EXECUTE ON FUNCTION verify_employee_pin(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION change_employee_pin(uuid, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION reset_employee_pin(uuid) TO anon, authenticated;
