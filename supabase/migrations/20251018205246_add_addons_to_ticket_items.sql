/*
  # Add add-ons fields to ticket_items

  1. Changes
    - Add `addon_details` column to `ticket_items` table (text field for add-on description)
    - Add `addon_price` column to `ticket_items` table (numeric field for add-on price)
  
  2. Notes
    - These fields allow tracking additional services/add-ons with custom details and pricing
    - Both fields are nullable (not all services will have add-ons)
    - Add-on price will be included in line_subtotal calculation
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'addon_details'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN addon_details text DEFAULT '';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'addon_price'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN addon_price numeric(10,2) DEFAULT 0.00;
  END IF;
END $$;
