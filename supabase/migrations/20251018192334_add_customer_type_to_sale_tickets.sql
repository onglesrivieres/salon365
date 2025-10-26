/*
  # Add customer_type to sale_tickets

  1. Changes
    - Add `customer_type` column to `sale_tickets` table
      - Type: text
      - Values: 'Appointment', 'Requested', 'Assigned'
      - Nullable: true (for existing records)
  
  2. Notes
    - This allows tracking how customers were acquired (appointment, walk-in request, or assigned)
    - Existing tickets will have null customer_type until edited
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'customer_type'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN customer_type text;
  END IF;
END $$;