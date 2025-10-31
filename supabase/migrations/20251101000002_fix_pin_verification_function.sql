/*
  # Fix PIN Verification Function Type Mismatch

  ## Overview
  Fixes the verify_employee_pin function to return the correct type for role_permission.
  The function was returning 'text' but role_permission is actually an enum type.

  ## Changes
  - Update verify_employee_pin function to return role_permission_type instead of text
  - This fixes the "structure of query does not match function result type" error
*/

-- Drop and recreate the verify_employee_pin function with correct return type
DROP FUNCTION IF EXISTS public.verify_employee_pin(text);

CREATE OR REPLACE FUNCTION public.verify_employee_pin(pin_input text)
RETURNS TABLE (
  employee_id uuid,
  display_name text,
  role text[],
  role_permission role_permission_type,
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

-- Grant execute permission
GRANT EXECUTE ON FUNCTION verify_employee_pin(text) TO anon, authenticated;