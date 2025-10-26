/*
  # Update Role Constraint for Spa Expert

  1. Changes
    - Drop existing `employees_role_valid` constraint
    - Add new constraint that includes 'Spa Expert' role
    - Spa Expert can be assigned to employees alongside other roles

  2. Purpose
    - Allow employees to have the 'Spa Expert' role
    - Spa Experts function like Technicians but cannot perform "Extensions des Ongles" services
*/

-- Drop the existing constraint
ALTER TABLE employees DROP CONSTRAINT IF EXISTS employees_role_valid;

-- Add the new constraint with Spa Expert included
ALTER TABLE employees ADD CONSTRAINT employees_role_valid
  CHECK (role <@ ARRAY['Technician', 'Receptionist', 'Supervisor', 'Manager', 'Owner', 'Spa Expert']::text[]);
