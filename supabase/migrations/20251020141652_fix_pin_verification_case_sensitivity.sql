/*
  # Fix PIN Verification Case Sensitivity

  ## Overview
  Updates the verify_employee_pin function to handle case-insensitive status checks,
  allowing employees with status 'active' or 'Active' to log in.

  ## Changes
  - Modify verify_employee_pin to use case-insensitive status comparison
  - Use LOWER() function to normalize status values

  ## Security
  - Maintains SECURITY DEFINER for controlled access
  - Only allows active employees to authenticate
*/

-- Update the verify_employee_pin function to be case-insensitive for status
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
  WHERE LOWER(e.status) = 'active'
    AND e.pin_code_hash IS NOT NULL
    AND e.pin_code_hash = extensions.crypt(pin_input, e.pin_code_hash)
  LIMIT 1;
END;
$$;
