/*
  # Add PIN Authentication to Employees

  1. Changes to Tables
    - Add `pin_code_hash` column to employees table
      - Stores bcrypt hash of 4-digit PIN
      - TEXT type, nullable initially for migration
    - Add `can_reset_pin` column to employees table
      - Boolean flag to control who can reset PINs
      - Defaults to false (only managers/owners should have this)
    - Add `pin_temp` column to employees table
      - Temporary PIN storage for reset functionality
      - Cleared after first login with temp PIN
    - Add `last_pin_change` column to employees table
      - Tracks when PIN was last changed
      - Timestamp with timezone

  2. Security Notes
    - PIN codes are stored as bcrypt hashes, never plain text
    - Only active employees can authenticate
    - Manager/Owner roles have can_reset_pin=true by default
    - Temporary PINs must be changed on first use

  3. Important Notes
    - Existing employees will need their PINs set by an admin
    - The application will handle PIN hashing client-side before sending
    - Session management handled in application layer
*/

-- Add PIN authentication columns to employees table
DO $$
BEGIN
  -- Add pin_code_hash column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'pin_code_hash'
  ) THEN
    ALTER TABLE employees ADD COLUMN pin_code_hash TEXT;
  END IF;

  -- Add can_reset_pin column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'can_reset_pin'
  ) THEN
    ALTER TABLE employees ADD COLUMN can_reset_pin BOOLEAN DEFAULT false;
  END IF;

  -- Add pin_temp column for temporary PINs
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'pin_temp'
  ) THEN
    ALTER TABLE employees ADD COLUMN pin_temp TEXT;
  END IF;

  -- Add last_pin_change timestamp
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'last_pin_change'
  ) THEN
    ALTER TABLE employees ADD COLUMN last_pin_change TIMESTAMPTZ;
  END IF;
END $$;

-- Set can_reset_pin=true for Manager and Owner roles
UPDATE employees 
SET can_reset_pin = true
WHERE role IN ('Manager', 'Owner') AND can_reset_pin = false;

-- Add comment to document PIN storage approach
COMMENT ON COLUMN employees.pin_code_hash IS 'Bcrypt hash of 4-digit PIN code. Never store plain text PINs.';
COMMENT ON COLUMN employees.can_reset_pin IS 'Permission flag for resetting other employees PINs. Typically true for Manager/Owner roles.';
COMMENT ON COLUMN employees.pin_temp IS 'Temporary PIN for password reset. Must be changed on first use.';
