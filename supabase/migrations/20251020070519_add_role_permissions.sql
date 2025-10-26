/*
  # Add Role-Based Permissions to Employees

  1. Changes to Tables
    - Add `role_permission` column to employees table
      - Enum type: 'Admin', 'Receptionist', 'Technician'
      - Defines access level independent of job role
      - NOT NULL with default based on existing role

  2. Permission Levels
    - **Admin**: Full access to all features (CRUD on everything)
    - **Receptionist**: Can create/edit open tickets, read-only for employees/services
    - **Technician**: View-only their own tickets and EOD totals

  3. Access Control Rules
    - Tickets: Admin (full), Receptionist (open tickets only), Technician (own tickets only)
    - End of Day: Admin/Receptionist (all data), Technician (own totals only)
    - Employees: Admin (full CRUD), Receptionist (read-only), Technician (no access)
    - Services: Admin (full CRUD), Receptionist (read-only), Technician (no access)

  4. Migration Notes
    - Existing 'Manager' and 'Owner' roles get 'Admin' permission
    - Existing 'Receptionist' role gets 'Receptionist' permission
    - Existing 'Technician' role gets 'Technician' permission
*/

-- Create enum type for role permissions if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'role_permission_type') THEN
    CREATE TYPE role_permission_type AS ENUM ('Admin', 'Receptionist', 'Technician');
  END IF;
END $$;

-- Add role_permission column to employees table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'role_permission'
  ) THEN
    ALTER TABLE employees ADD COLUMN role_permission role_permission_type;
  END IF;
END $$;

-- Set default role_permission based on existing role
UPDATE employees
SET role_permission = CASE
  WHEN role IN ('Manager', 'Owner') THEN 'Admin'::role_permission_type
  WHEN role = 'Receptionist' THEN 'Receptionist'::role_permission_type
  WHEN role = 'Technician' THEN 'Technician'::role_permission_type
  ELSE 'Technician'::role_permission_type
END
WHERE role_permission IS NULL;

-- Make role_permission NOT NULL after setting defaults
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' 
    AND column_name = 'role_permission'
    AND is_nullable = 'YES'
  ) THEN
    ALTER TABLE employees ALTER COLUMN role_permission SET NOT NULL;
  END IF;
END $$;

-- Add comment to document permission levels
COMMENT ON COLUMN employees.role_permission IS 'Access permission level: Admin (full access), Receptionist (limited write access), Technician (view-only own data)';
