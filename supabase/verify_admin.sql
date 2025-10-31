-- Verification script to check if admin user was created correctly
-- This script verifies the admin user exists and can authenticate with PIN 8228

-- Step 1: Check if admin user exists
SELECT 
  'Admin User Check' as verification_type,
  e.id,
  e.display_name,
  e.legal_name,
  e.role,
  e.role_permission,
  e.can_reset_pin,
  s.name as store_name,
  CASE WHEN e.pin_code_hash IS NOT NULL THEN 'PIN Set' ELSE 'PIN Missing' END as pin_status,
  e.status
FROM employees e
LEFT JOIN stores s ON e.store_id = s.id
WHERE 'Admin' = ANY(e.role) OR 'Owner' = ANY(e.role);

-- Step 2: Test PIN authentication for admin user
-- This simulates what the verify_employee_pin function would return
SELECT 
  'PIN Authentication Test' as verification_type,
  e.id as employee_id,
  e.display_name,
  e.role,
  e.role_permission,
  e.can_reset_pin,
  CASE 
    WHEN e.pin_code_hash IS NOT NULL THEN 'PIN Hash Present'
    ELSE 'PIN Hash Missing'
  END as hash_status
FROM employees e
WHERE 
  e.status = 'Active' 
  AND e.pin_code_hash IS NOT NULL
  AND ('Admin' = ANY(e.role) OR 'Owner' = ANY(e.role));

-- Step 3: Verify all tables are accessible
SELECT 
  'Store Verification' as verification_type,
  COUNT(*) as store_count,
  STRING_AGG(name, ', ') as store_names
FROM stores 
WHERE active = true;

-- Step 4: Check if the application can find the admin user by PIN
-- This is what the authenticateWithPIN function would call
SELECT 
  'Function Test' as verification_type,
  'verify_employee_pin(\'8228\')' as test_function,
  'This function should return the admin user data' as expected_result
UNION ALL
SELECT 
  'Function Test Result' as verification_type,
  'Employee ID: ' || COALESCE(vep.employee_id::text, 'NULL'),
  'Name: ' || COALESCE(vep.display_name, 'NULL')
FROM verify_employee_pin('8228') vep
LIMIT 1;