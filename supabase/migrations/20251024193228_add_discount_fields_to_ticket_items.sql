/*
  # Add Discount Fields to Ticket Items

  1. New Columns
    - `discount_percentage` (numeric) - The discount percentage applied to the ticket item (0-100)
    - `discount_amount` (numeric) - The fixed discount amount in dollars applied to the ticket item
  
  2. Changes
    - Added `discount_percentage` column to `ticket_items` table with default value of 0.00
    - Added `discount_amount` column to `ticket_items` table with default value of 0.00
    - Both fields are nullable to allow for optional discounts
    
  3. Notes
    - Discount percentage is stored as a number (e.g., 10 for 10%)
    - Discount amount is stored in dollars (e.g., 5.00 for $5)
    - These fields allow flexibility in applying either percentage or fixed amount discounts
*/

-- Add discount_percentage column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'discount_percentage'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN discount_percentage numeric DEFAULT 0.00;
  END IF;
END $$;

-- Add discount_amount column
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'discount_amount'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN discount_amount numeric DEFAULT 0.00;
  END IF;
END $$;