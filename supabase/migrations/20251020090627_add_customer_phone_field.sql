/*
  # Add Customer Phone Field

  This migration adds a customer_phone field to the sale_tickets table to separate customer name and phone number.

  ## Changes
  
  1. Tables Modified
    - `sale_tickets`: Add `customer_phone` column to store customer phone number separately from name

  ## Notes
  - This allows better organization of customer information
  - Phone number field is optional (nullable)
  - Default value is empty string for consistency
*/

-- Add customer_phone column to sale_tickets table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'customer_phone'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN customer_phone text DEFAULT '';
  END IF;
END $$;