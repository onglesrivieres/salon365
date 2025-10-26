/*
  # Remove Subtotal Columns

  This migration removes subtotal-related columns from the database as they are no longer used in calculations.

  ## Changes
  
  1. Tables Modified
    - `sale_tickets`: Remove `subtotal` column (only `total` is needed)
    - `ticket_items`: Remove `line_subtotal` column (calculated on the fly from qty * price_each + addon_price)

  ## Notes
  - This is a destructive operation, but subtotal values are redundant and can be recalculated from other fields
  - The `total` column in `sale_tickets` remains and stores the final total
  - Line totals in `ticket_items` are calculated dynamically in the application
*/

-- Remove subtotal column from sale_tickets table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'subtotal'
  ) THEN
    ALTER TABLE sale_tickets DROP COLUMN subtotal;
  END IF;
END $$;

-- Remove line_subtotal column from ticket_items table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'line_subtotal'
  ) THEN
    ALTER TABLE ticket_items DROP COLUMN line_subtotal;
  END IF;
END $$;