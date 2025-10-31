-- Remove unwanted stores from the database while keeping only Sans Souci Ongles & Spa
-- This script directly cleans up the database

-- Step 1: Delete store-specific service configurations for unwanted stores
DELETE FROM store_services 
WHERE store_id IN (
    SELECT id FROM stores 
    WHERE name IN ('Ongles Maily', 'Ongles Charlesbourg', 'Ongles Rivières')
);

-- Step 2: Delete employee-store assignments for unwanted stores  
DELETE FROM employee_stores 
WHERE store_id IN (
    SELECT id FROM stores 
    WHERE name IN ('Ongles Maily', 'Ongles Charlesbourg', 'Ongles Rivières')
);

-- Step 3: Delete the unwanted stores themselves
DELETE FROM stores 
WHERE name IN ('Ongles Maily', 'Ongles Charlesbourg', 'Ongles Rivières');

-- Step 4: Verify only Sans Souci Ongles & Spa remains
SELECT name, code, active FROM stores ORDER BY name;

-- Step 5: Show final store count
DO $$
DECLARE
    store_count integer;
BEGIN
    SELECT COUNT(*) INTO store_count FROM stores WHERE active = true;
    RAISE NOTICE 'Active stores count after cleanup: %', store_count;
END $$;