/*
  # Rename tip_customer to tip_customer_cash and remove tip_receptionist_card

  1. Changes
    - Rename `tip_customer` column to `tip_customer_cash` in ticket_items table
    - Drop `tip_receptionist_card` column from ticket_items table
  
  2. Notes
    - This preserves all existing tip_customer data under the new name tip_customer_cash
    - Removes the tip_receptionist_card column completely
    - Other tip columns (tip_receptionist, tip_customer_card) remain unchanged
*/

-- Rename tip_customer to tip_customer_cash
ALTER TABLE ticket_items 
RENAME COLUMN tip_customer TO tip_customer_cash;

-- Drop tip_receptionist_card column
ALTER TABLE ticket_items 
DROP COLUMN IF EXISTS tip_receptionist_card;
