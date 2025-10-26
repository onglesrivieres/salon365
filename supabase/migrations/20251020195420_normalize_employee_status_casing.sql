/*
  # Normalize Employee Status Casing

  ## Overview
  The employees table has inconsistent status values - some 'active', some 'Active'.
  This causes issues with queries and can lead to unpredictable behavior.

  ## Issue
  - 27 employees have status = 'active' (lowercase)
  - 1 employee has status = 'Active' (uppercase)
  - Functions use LOWER(status) = 'active' but this is inefficient

  ## Fix
  - Normalize all status values to lowercase
  - This ensures consistency across the entire database

  ## Impact
  - All status checks will work consistently
  - No performance impact - simple UPDATE
*/

-- Normalize all employee status values to lowercase
UPDATE employees
SET status = LOWER(status)
WHERE status IS NOT NULL AND status != LOWER(status);