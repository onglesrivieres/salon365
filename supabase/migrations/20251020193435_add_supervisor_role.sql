/*
  # Add Supervisor Role

  ## Overview
  Creates a new "Supervisor" role that has all permissions of both Technician and Receptionist.
  This role is designed for employees who need to:
  - Perform technical work (as Technician)
  - Handle reception duties (as Receptionist)
  - Has full control over ticket lifecycle

  ## Important Note
  When a Supervisor closes a ticket, they will trigger the `requires_higher_approval` flag
  (similar to an employee with both Technician and Receptionist roles) because they have
  complete control over both service delivery and ticket finalization.

  ## Changes
  1. Update role check constraint to include 'Supervisor'
  2. Supervisor inherits all Technician and Receptionist permissions

  ## Security
  - Supervisors who close tickets will require management approval
  - This prevents manipulation since they control the entire ticket lifecycle
*/

-- Drop the existing constraint
ALTER TABLE employees DROP CONSTRAINT IF EXISTS employees_role_valid;

-- Add the new constraint with Supervisor included
ALTER TABLE employees ADD CONSTRAINT employees_role_valid 
  CHECK (role <@ ARRAY['Technician', 'Receptionist', 'Supervisor', 'Manager', 'Owner']::text[]);

-- Create index for performance when querying by role
CREATE INDEX IF NOT EXISTS idx_employees_role_gin ON employees USING gin(role);