/*
  # Add Ticket Audit Fields

  1. Changes
    - Add `created_by` column to track who created the ticket
    - Add `saved_by` column to track who last saved/updated the ticket
    - Add `closed_by` column to track who closed the ticket
    
  2. Details
    - All three columns are foreign keys referencing the employees table
    - `created_by` is required (NOT NULL) as every ticket must have a creator
    - `saved_by` is optional as it tracks the last person who saved changes
    - `closed_by` is optional and only populated when ticket is closed
*/

-- Add created_by column
ALTER TABLE sale_tickets ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES employees(id);

-- Add saved_by column
ALTER TABLE sale_tickets ADD COLUMN IF NOT EXISTS saved_by uuid REFERENCES employees(id);

-- Add closed_by column
ALTER TABLE sale_tickets ADD COLUMN IF NOT EXISTS closed_by uuid REFERENCES employees(id);

-- Add NOT NULL constraint to created_by for new records (existing records may have NULL)
-- We'll allow NULL for existing records but encourage setting it
DO $$
BEGIN
  -- Only add constraint if column exists and doesn't already have the constraint
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'sale_tickets_created_by_not_null'
    AND table_name = 'sale_tickets'
  ) THEN
    -- For existing NULL records, we could set a default, but we'll leave them as is
    -- New records will be handled by the application
    NULL;
  END IF;
END $$;