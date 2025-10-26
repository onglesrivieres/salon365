/*
  # Add customer_type Column to sale_tickets

  ## Overview
  This migration adds the missing customer_type column to the sale_tickets table
  that is required by the application.

  ## Changes

  ### 1. Add column to sale_tickets table
  - `customer_type` (text) - Type of customer (Appointment, Requested, Assigned)

  ## Notes
  - This allows tracking how customers were acquired
  - Nullable to support existing records
  - Common values: 'Appointment', 'Requested', 'Assigned'
*/

-- Add customer_type column to sale_tickets table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'customer_type'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN customer_type text;
  END IF;
END $$;
