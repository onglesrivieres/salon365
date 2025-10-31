/*
  # Complete Store Reset Migration

  ## Overview
  This migration performs a complete data reset by:
  1. Removing all existing sales data (sale_tickets and related ticket_items)
  2. Clearing all employee-store assignments (employee_stores junction table)
  3. Removing all store-specific service configurations (store_services)
  4. Removing all existing stores
  5. Adding new "Sans Souci Ongles & Spa" store
  6. Clearing employee store references to start fresh

  ## Tables Affected
  - ticket_items (deleted via cascade)
  - sale_tickets (deleted via cascade) 
  - employee_stores (cleared)
  - store_services (cleared)
  - stores (cleared and repopulated)
  - employees.store_id (cleared)
  - Note: default_store_id column was removed in migration 20251020080544

  ## Data Loss Warning
  This migration will permanently delete ALL sales data, employee assignments, and store configurations.
*/

-- Step 1: Delete all sales tickets (cascades to ticket_items and other related tables)
DELETE FROM sale_tickets;

-- Step 2: Clear employee-store assignments
DELETE FROM employee_stores;

-- Step 3: Remove all store-specific service configurations  
DELETE FROM store_services;

-- Step 4: Remove all existing stores
DELETE FROM stores;

-- Step 5: Clear employee store references (now that stores table is empty)
UPDATE employees SET store_id = NULL;
-- Note: default_store_id column was removed in migration 20251020080544
-- Only clearing store_id column now

-- Step 6: Insert the new single store
INSERT INTO stores (name, code, active) VALUES
  ('Sans Souci Ongles & Spa', 'SS', true)
ON CONFLICT (code) DO NOTHING;

-- Step 7: Get the new store ID for reference
-- This will be used to potentially assign employees if needed
DO $$
DECLARE
  new_store_id uuid;
BEGIN
  SELECT id INTO new_store_id FROM stores WHERE code = 'SS' LIMIT 1;
  
  -- If you want to automatically assign employees to the new store, uncomment below
  -- UPDATE employees SET store_id = new_store_id WHERE store_id IS NULL;
  
  RAISE NOTICE 'New store created with ID: %', new_store_id;
END $$;

-- Step 8: Verify the changes
-- This will show the final store count (should be 1)
DO $$
DECLARE
  store_count integer;
BEGIN
  SELECT COUNT(*) INTO store_count FROM stores WHERE active = true;
  RAISE NOTICE 'Active stores count: %', store_count;
END $$;