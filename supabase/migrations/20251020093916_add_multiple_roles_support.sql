/*
  # Add Multiple Roles Support for Employees

  1. Changes
    - Modify `employees` table to change the `role` column from single text to text array
    - Update existing data to convert single role strings to arrays
    - Add check constraint to ensure at least one role is assigned
  
  2. Migration Steps
    - Add new column `roles` as text array
    - Copy existing `role` data to `roles` array
    - Drop old `role` column
    - Rename `roles` to `role`
    - Add constraint to ensure array is not empty
*/

-- Add new roles column as array
ALTER TABLE employees ADD COLUMN IF NOT EXISTS roles text[] DEFAULT ARRAY[]::text[];

-- Migrate existing role data to roles array
UPDATE employees SET roles = ARRAY[role]::text[] WHERE roles = ARRAY[]::text[];

-- Drop the old role column
ALTER TABLE employees DROP COLUMN IF EXISTS role;

-- Rename roles to role
ALTER TABLE employees RENAME COLUMN roles TO role;

-- Add check constraint to ensure at least one role
ALTER TABLE employees ADD CONSTRAINT employees_role_not_empty CHECK (array_length(role, 1) > 0);

-- Add check constraint to ensure valid roles
ALTER TABLE employees ADD CONSTRAINT employees_role_valid CHECK (
  role <@ ARRAY['Technician', 'Receptionist', 'Manager', 'Owner']::text[]
);