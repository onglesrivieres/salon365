/*
  # Add function to set specific employee PIN

  Creates a function to set a specific 4-digit PIN for an employee.
  This allows administrators to set custom PINs instead of random ones.
*/

CREATE OR REPLACE FUNCTION public.set_employee_pin(emp_id uuid, new_pin text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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
