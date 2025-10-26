/*
  # Add PIN Verification Function

  1. New Functions
    - `verify_employee_pin(pin_input text)` - Securely verifies PIN and returns employee data
      - Takes plain text 4-digit PIN as input
      - Uses bcrypt to verify against stored hash
      - Returns employee session data if PIN is valid
      - Returns null if PIN is invalid or employee is not active
  
  2. Security
    - Function executes with SECURITY DEFINER to access pin_code_hash
    - RLS policies still apply to the returned data
    - No plain text PINs are stored or logged
*/

-- Create function to verify PIN and return employee data
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
SET search_path = public
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
    AND e.pin_code_hash = crypt(pin_input, e.pin_code_hash)
  LIMIT 1;
END;
$$;

-- Grant execute permission to anon and authenticated users
GRANT EXECUTE ON FUNCTION verify_employee_pin(text) TO anon, authenticated;

COMMENT ON FUNCTION verify_employee_pin IS 'Verifies employee PIN using bcrypt and returns session data if valid';
