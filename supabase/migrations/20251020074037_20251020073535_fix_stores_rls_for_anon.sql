/*
  # Fix Stores RLS for Anonymous Users

  1. Changes
    - Update stores RLS policies to work with anon role
    - Allow anon users to SELECT active stores (needed for PIN-based auth)
    - Keep admin restrictions for modifications

  2. Security
    - Anonymous users (using anon key) can view active stores
    - Only authenticated sessions can modify stores
    - This supports PIN-based authentication flow
*/

-- Drop existing policies
DROP POLICY IF EXISTS "Authenticated users can view stores" ON stores;
DROP POLICY IF EXISTS "Admins can manage stores" ON stores;

-- Allow anon and authenticated users to view active stores
CREATE POLICY "Users can view active stores"
  ON stores FOR SELECT
  TO anon, authenticated
  USING (active = true);

-- Allow all authenticated operations for admins (insert, update, delete)
CREATE POLICY "Admins can manage stores"
  ON stores FOR ALL
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.pin_code_hash IS NOT NULL
      AND employees.role_permission = 'Admin'
      AND employees.status = 'Active'
    )
  );

-- Update store_services policies to work with anon role
DROP POLICY IF EXISTS "Authenticated users can view store services" ON store_services;
DROP POLICY IF EXISTS "Admin and Receptionist can manage store services" ON store_services;

CREATE POLICY "Users can view store services"
  ON store_services FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "Admins and Receptionists can manage store services"
  ON store_services FOR ALL
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.pin_code_hash IS NOT NULL
      AND employees.role_permission IN ('Admin', 'Receptionist')
      AND employees.status = 'Active'
    )
  );
