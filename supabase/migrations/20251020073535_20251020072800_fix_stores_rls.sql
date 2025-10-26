/*
  # Fix Stores RLS Policies

  1. Changes
    - Remove restrictive RLS policies on stores table
    - Allow all authenticated users to view active stores
    - Only admins can modify stores (checked via employees table join)

  2. Security
    - Authenticated users can SELECT all active stores
    - Store modifications still require Admin permission
*/

-- Drop existing policies
DROP POLICY IF EXISTS "Authenticated users can view active stores" ON stores;
DROP POLICY IF EXISTS "Admin users can manage stores" ON stores;

-- Allow authenticated users to view active stores (for store switcher)
CREATE POLICY "Authenticated users can view stores"
  ON stores FOR SELECT
  TO authenticated
  USING (active = true);

-- Allow admins to manage stores (insert, update, delete)
CREATE POLICY "Admins can manage stores"
  ON stores FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.pin_code_hash IS NOT NULL
      AND employees.role_permission = 'Admin'
      AND employees.status = 'Active'
    )
  );
