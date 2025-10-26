/*
  # Add Pay Type to Employees

  ## Overview
  Add a pay_type column to the employees table to distinguish between hourly and daily paid employees.
  This will be used to control the visibility of the Check-in/Out button on the Store Switcher page.

  ## Changes
  1. Add `pay_type` column to employees table
     - Type: text with constraint to only allow 'hourly' or 'daily'
     - Default: 'hourly' (for backward compatibility)
  2. Add check constraint to ensure valid pay_type values
  3. Backfill existing employees with 'hourly' as default

  ## Usage
  - Only employees with pay_type = 'hourly' will see the Check-in/Out button
  - Employees with pay_type = 'daily' will not need to track time
  - Only admins and managers can configure this field

  ## Security
  - No RLS changes needed (existing policies apply)
*/

-- Add pay_type column to employees table
ALTER TABLE employees ADD COLUMN IF NOT EXISTS pay_type text DEFAULT 'hourly';

-- Add check constraint to ensure valid pay_type values
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'employees_pay_type_valid' 
    AND table_name = 'employees'
  ) THEN
    ALTER TABLE employees ADD CONSTRAINT employees_pay_type_valid 
    CHECK (pay_type IN ('hourly', 'daily'));
  END IF;
END $$;

-- Backfill existing employees with 'hourly' as default
UPDATE employees SET pay_type = 'hourly' WHERE pay_type IS NULL;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_employees_pay_type ON employees(pay_type);