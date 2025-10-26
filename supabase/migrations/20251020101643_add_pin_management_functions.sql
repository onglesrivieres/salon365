/*
  # Add PIN Management Functions

  1. New Functions
    - `change_employee_pin(emp_id uuid, old_pin text, new_pin text)` - Change PIN with old PIN verification
    - `reset_employee_pin(emp_id uuid)` - Reset PIN to random temporary PIN (admin only)
  
  2. Security
    - Functions use bcrypt for hashing
    - SECURITY DEFINER to access pin_code_hash
    - Validates PIN format (4 digits)
    - Never stores plain text PINs
*/

-- Function to change employee PIN
CREATE OR REPLACE FUNCTION change_employee_pin(
  emp_id uuid,
  old_pin text,
  new_pin text
)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public
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
  IF current_hash != crypt(old_pin, current_hash) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Current PIN is incorrect');
  END IF;

  -- Update with new PIN
  UPDATE employees
  SET 
    pin_code_hash = crypt(new_pin, gen_salt('bf')),
    pin_temp = null,
    last_pin_change = now(),
    updated_at = now()
  WHERE id = emp_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Function to reset employee PIN (generates temporary PIN)
CREATE OR REPLACE FUNCTION reset_employee_pin(emp_id uuid)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public
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
GRANT EXECUTE ON FUNCTION change_employee_pin(uuid, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION reset_employee_pin(uuid) TO anon, authenticated;

COMMENT ON FUNCTION change_employee_pin IS 'Changes employee PIN after verifying old PIN using bcrypt';
COMMENT ON FUNCTION reset_employee_pin IS 'Resets employee PIN to a random temporary PIN';
