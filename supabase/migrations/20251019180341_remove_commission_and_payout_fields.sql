/*
  # Remove Commission and Payout Fields

  ## Overview
  Removes all commission and payout-related fields from the employees table.

  ## Changes
  1. Drop payout_rule_type column from employees
  2. Drop payout_commission_pct column from employees
  3. Drop payout_hourly_rate column from employees
  4. Drop payout_flat_per_service column from employees

  ## Notes
  - This migration removes all commission and payout tracking functionality
  - Existing data in these columns will be permanently deleted
*/

-- Remove payout and commission fields from employees table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'payout_rule_type'
  ) THEN
    ALTER TABLE employees DROP COLUMN payout_rule_type;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'payout_commission_pct'
  ) THEN
    ALTER TABLE employees DROP COLUMN payout_commission_pct;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'payout_hourly_rate'
  ) THEN
    ALTER TABLE employees DROP COLUMN payout_hourly_rate;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'payout_flat_per_service'
  ) THEN
    ALTER TABLE employees DROP COLUMN payout_flat_per_service;
  END IF;
END $$;