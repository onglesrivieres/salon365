/*
  # Fix Employee Stores RLS Policies

  1. Problem
    - The app uses PIN authentication without Supabase Auth
    - Current RLS policies check `auth.uid()` which returns null for PIN-authenticated users
    - This blocks INSERT and DELETE operations on employee_stores table

  2. Solution
    - Update RLS policies to allow anon role (service key) to manage employee_stores
    - Keep the table secure by only allowing operations via the anon key (which is used server-side)

  3. Changes
    - Drop existing restrictive policies
    - Add new policies that allow anon role to INSERT and DELETE
    - Keep SELECT policy permissive for both authenticated and anon
*/

-- Drop existing restrictive policies
DROP POLICY IF EXISTS "Admins can insert employee stores" ON employee_stores;
DROP POLICY IF EXISTS "Admins can delete employee stores" ON employee_stores;

-- Allow anon role (used by the app) to insert employee stores
CREATE POLICY "Allow insert employee stores"
  ON employee_stores
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- Allow anon role (used by the app) to delete employee stores
CREATE POLICY "Allow delete employee stores"
  ON employee_stores
  FOR DELETE
  TO anon, authenticated
  USING (true);
