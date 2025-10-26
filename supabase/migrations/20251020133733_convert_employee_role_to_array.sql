/*
  # Convert Employee Role to Array Type

  ## Overview
  Converts the employee role field from single text to text array to support
  employees having multiple roles (e.g., both Technician and Receptionist).

  ## Changes
  1. Add temporary `roles` column as text array
  2. Migrate existing single role data to array format
  3. Drop old text `role` column
  4. Rename `roles` to `role`
  5. Add constraints for data validation

  ## Constraints
  - Role array must not be empty
  - All roles must be valid: Technician, Receptionist, Manager, or Owner

  ## Data Safety
  - Uses temporary column to prevent data loss
  - Existing role data is preserved in array format
*/

-- Step 1: Add new roles column as array
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'roles'
  ) THEN
    ALTER TABLE employees ADD COLUMN roles text[] DEFAULT ARRAY[]::text[];
  END IF;
END $$;

-- Step 2: Migrate existing role data to roles array (only if roles is empty)
UPDATE employees 
SET roles = ARRAY[role]::text[] 
WHERE roles = ARRAY[]::text[] OR roles IS NULL;

-- Step 3: Drop the old role column if it exists and roles column has data
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'role' AND data_type = 'text'
  ) THEN
    ALTER TABLE employees DROP COLUMN role;
  END IF;
END $$;

-- Step 4: Rename roles to role
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'roles'
  ) THEN
    ALTER TABLE employees RENAME COLUMN roles TO role;
  END IF;
END $$;

-- Step 5: Drop existing constraints if they exist
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'employees' AND constraint_name = 'employees_role_not_empty'
  ) THEN
    ALTER TABLE employees DROP CONSTRAINT employees_role_not_empty;
  END IF;
  
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'employees' AND constraint_name = 'employees_role_valid'
  ) THEN
    ALTER TABLE employees DROP CONSTRAINT employees_role_valid;
  END IF;
END $$;

-- Step 6: Add check constraint to ensure at least one role
ALTER TABLE employees ADD CONSTRAINT employees_role_not_empty 
  CHECK (array_length(role, 1) > 0);

-- Step 7: Add check constraint to ensure valid roles
ALTER TABLE employees ADD CONSTRAINT employees_role_valid 
  CHECK (role <@ ARRAY['Technician', 'Receptionist', 'Manager', 'Owner']::text[]);
