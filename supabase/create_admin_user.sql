/*
  # Create Admin User Script

  This script creates an admin user with full permissions and PIN 8228.
*/

-- Step 1: Get the store ID for "Sans Souci Ongles & Spa"
DO $$
DECLARE
  admin_store_id uuid;
  admin_user_id uuid;
BEGIN

  -- Get the store ID for the main store
  SELECT id INTO admin_store_id 
  FROM stores 
  WHERE name = 'Sans Souci Ongles & Spa' 
  AND active = true
  LIMIT 1;

  -- If store doesn't exist, create it
  IF admin_store_id IS NULL THEN
    INSERT INTO stores (name, code, active) 
    VALUES ('Sans Souci Ongles & Spa', 'SS', true)
    RETURNING id INTO admin_store_id;
  END IF;

  -- Step 2: Remove existing admin users to avoid conflicts
  DELETE FROM employees 
  WHERE 'Admin' = ANY(role) OR 'Owner' = ANY(role);

  -- Step 3: Create the admin user
  INSERT INTO employees (
    legal_name,
    display_name,
    role,
    role_permission,
    status,
    can_reset_pin,
    store_id,
    notes,
    pay_type
  ) VALUES (
    'Administrator',
    'Admin',
    ARRAY['Admin', 'Owner', 'Manager'],
    'Admin',
    'Active',
    true,
    admin_store_id,
    'System Administrator with full access',
    'hourly'
  )
  RETURNING id INTO admin_user_id;

  -- Step 4: Set the PIN 8228 for the admin user
  -- First ensure pgcrypto extension is available
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
  
  -- Update the admin user with PIN 8228
  UPDATE employees
  SET 
    pin_code_hash = extensions.crypt('8228', extensions.gen_salt('bf')),
    pin_temp = NULL,
    last_pin_change = now(),
    updated_at = now()
  WHERE id = admin_user_id;

  -- Step 5: Verify the user was created correctly
  RAISE NOTICE 'Admin user created with ID: %', admin_user_id;
  RAISE NOTICE 'Store ID: %', admin_store_id;
  RAISE NOTICE 'Display Name: Admin';
  RAISE NOTICE 'Roles: Admin, Owner, Manager';
  RAISE NOTICE 'PIN: 8228';

END $$;

-- Step 6: Verify the admin user exists and can authenticate
SELECT 
  e.id,
  e.display_name,
  e.role,
  e.role_permission,
  e.can_reset_pin,
  s.name as store_name,
  CASE WHEN e.pin_code_hash IS NOT NULL THEN 'PIN Set' ELSE 'PIN Missing' END as pin_status
FROM employees e
LEFT JOIN stores s ON e.store_id = s.id
WHERE 'Admin' = ANY(e.role)
OR 'Owner' = ANY(e.role);