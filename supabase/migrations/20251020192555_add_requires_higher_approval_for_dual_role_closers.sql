/*
  # Add Higher Approval Requirement for Dual-Role Technicians

  ## Overview
  Implements enhanced security for tickets closed by technicians who also have receptionist permissions.
  These tickets require approval from higher management (Admin/Manager) to prevent manipulation.

  ## Problem
  A technician with receptionist permissions can:
  1. Perform the service (as technician)
  2. Close the ticket and set prices (as receptionist)
  3. This creates opportunity for manipulation

  ## Solution
  - Add `requires_higher_approval` boolean column to track these cases
  - Add `closed_by_roles` jsonb column to store the roles of the person who closed the ticket
  - When ticket is closed, check if closer has both Technician and Receptionist roles
  - If yes, set `requires_higher_approval = true`
  - Only Admin/Manager/Owner can approve these tickets

  ## Changes
  1. New Columns:
     - `requires_higher_approval` (boolean) - Indicates ticket needs admin/manager approval
     - `closed_by_roles` (jsonb) - Stores roles array of the employee who closed the ticket
  
  2. Security:
     - Prevents dual-role employees from having complete control over ticket lifecycle
     - Requires separation of duties for ticket approval
*/

-- Add requires_higher_approval column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'requires_higher_approval'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN requires_higher_approval boolean DEFAULT false;
  END IF;
END $$;

-- Add closed_by_roles column to track roles at closing time
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'closed_by_roles'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN closed_by_roles jsonb DEFAULT '[]'::jsonb;
  END IF;
END $$;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_sale_tickets_requires_higher_approval 
  ON sale_tickets(requires_higher_approval) 
  WHERE requires_higher_approval = true;