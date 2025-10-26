/*
  # Remove default_store_id Column

  1. Changes
    - Remove `default_store_id` column from `employees` table
    - This column is no longer needed as users now select their store at login
    - If a user has only one store assigned, they will be automatically logged into that store

  2. Notes
    - The multi-store assignment is now handled via the `employee_stores` junction table
    - No data migration needed as the column was optional and not critical
*/

-- Remove default_store_id column from employees table
ALTER TABLE employees DROP COLUMN IF EXISTS default_store_id;
