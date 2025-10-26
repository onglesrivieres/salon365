/*
  # Add Add-on Columns to Ticket Items

  ## Overview
  This migration adds the missing addon columns to the ticket_items table
  that are required by the application.

  ## Changes

  ### 1. Add columns to ticket_items table
  - `addon_details` (text) - Description of add-ons
  - `addon_price` (numeric) - Price of add-ons

  ## Notes
  - These fields allow tracking additional services/add-ons with custom details and pricing
  - Both fields are nullable (not all services will have add-ons)
  - Add-on price will be included in total calculations
*/

-- Add addon columns to ticket_items table
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
