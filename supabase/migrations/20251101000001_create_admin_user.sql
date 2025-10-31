/*
  # Create Admin User Script

  This script creates an admin user with full permissions and PIN 8228.
  The admin user will have access to ALL stores via the employee_stores junction table.
*/

-- Step 1: Get or create the main store, and get all active stores
DO $$
DECLARE
  main_store_id uuid;
  admin_user_id uuid;
  store_record RECORD;
BEGIN

  -- Get the store ID for the main store (Sans Souci Ongles & Spa)
  SELECT id INTO main_store_id
  FROM stores
  WHERE name = 'Sans Souci Ongles & Spa'
  AND active = true
  LIMIT 1;

  -- If store doesn't exist, create it
  IF main_store_id IS NULL THEN
    INSERT INTO stores (name, code, active)
    VALUES ('Sans Souci Ongles & Spa', 'SS', true)
    RETURNING id INTO main_store_id;
  END IF;

  -- Step 2: Remove existing admin users to avoid conflicts
  DELETE FROM employee_stores WHERE employee_id IN (
    SELECT id FROM employees WHERE 'Admin' = ANY(role) OR 'Owner' = ANY(role)
  );
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
    ARRAY['Owner', 'Manager'],
    'Admin',
    'Active',
    true,
    main_store_id,
    'System Administrator with access to all stores',
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

  -- Step 5: Assign admin user to ALL stores via employee_stores junction table
  -- First ensure the employee_stores table exists
  CREATE TABLE IF NOT EXISTS employee_stores (
    employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now(),
    PRIMARY KEY (employee_id, store_id)
  );

  -- Enable RLS on employee_stores
  ALTER TABLE employee_stores ENABLE ROW LEVEL SECURITY;

  -- Create RLS policies for employee_stores
  CREATE POLICY "Allow all access to employee_stores"
    ON employee_stores FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

  -- Assign admin to all active stores
  FOR store_record IN SELECT id, name FROM stores WHERE active = true LOOP
    INSERT INTO employee_stores (employee_id, store_id)
    VALUES (admin_user_id, store_record.id)
    ON CONFLICT (employee_id, store_id) DO NOTHING;
    
    RAISE NOTICE 'Admin user assigned to store: %', store_record.name;
  END LOOP;

  -- Step 6: Verify the user was created correctly
  RAISE NOTICE 'Admin user created with ID: %', admin_user_id;
  RAISE NOTICE 'Display Name: Admin';
  RAISE NOTICE 'Roles: Owner, Manager';
  RAISE NOTICE 'Role Permission: Admin';
  RAISE NOTICE 'PIN: 8228';
  RAISE NOTICE 'Access to all stores via employee_stores junction table';

END $$;

-- Step 7: Verify the admin user exists and has access to all stores
SELECT
  e.id,
  e.display_name,
  e.role,
  e.role_permission,
  e.can_reset_pin,
  s.name as store_name,
  CASE WHEN e.pin_code_hash IS NOT NULL THEN 'PIN Set' ELSE 'PIN Missing' END as pin_status
FROM employees e
LEFT JOIN employee_stores es ON e.id = es.employee_id
LEFT JOIN stores s ON es.store_id = s.id
WHERE 'Admin' = ANY(e.role)
OR 'Owner' = ANY(e.role)
ORDER BY s.name;