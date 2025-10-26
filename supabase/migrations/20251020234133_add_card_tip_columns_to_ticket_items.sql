/*
  # Add Card Tip Columns to Ticket Items

  ## Overview
  This migration adds separate tracking for card tips versus cash tips in the ticket_items table.
  When tickets are closed with Card payment method, tips are stored in dedicated card tip fields,
  while cash payment tips remain in the existing tip fields.

  ## Changes

  ### 1. Add columns to ticket_items table
  - `tip_customer_card` (numeric) - Tip from customer paid via card
  - `tip_receptionist_card` (numeric) - Tip from receptionist paired via card

  ### 2. Performance Indexes
  - Add indexes on new card tip columns for efficient reporting queries

  ## Notes
  - Existing `tip_customer` and `tip_receptionist` columns will be used for cash tips
  - Both card and cash tip columns default to 0.00
  - This enables separate tracking and reporting of tip amounts by payment method
  - Reports can now show technicians their card tips separately from cash tips
*/

-- Add card tip columns to ticket_items table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'tip_customer_card'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN tip_customer_card numeric(10,2) DEFAULT 0.00;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'tip_receptionist_card'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN tip_receptionist_card numeric(10,2) DEFAULT 0.00;
  END IF;
END $$;

-- Add performance indexes for reporting queries
CREATE INDEX IF NOT EXISTS idx_ticket_items_tip_customer_card 
  ON ticket_items(tip_customer_card) WHERE tip_customer_card > 0;

CREATE INDEX IF NOT EXISTS idx_ticket_items_tip_receptionist_card 
  ON ticket_items(tip_receptionist_card) WHERE tip_receptionist_card > 0;

-- Analyze table to update query planner statistics
ANALYZE ticket_items;