/*
  # Add Multi-Store Support for Employees

  1. New Tables
    - `employee_stores` (junction table)
      - `employee_id` (uuid, foreign key to employees)
      - `store_id` (uuid, foreign key to stores)
      - `created_at` (timestamp)
      - Primary key on (employee_id, store_id)

  2. Changes
    - Creates a many-to-many relationship between employees and stores
    - Migrates existing `store_id` data from employees table to the new junction table
    - Keeps the `store_id` column in employees table for backward compatibility (will be deprecated)

  3. Security
    - Enable RLS on `employee_stores` table
    - Add policies for authenticated users to read employee-store associations
    - Add policies for admins to manage employee-store associations

  4. Notes
    - Employees can now be assigned to multiple stores
    - The UI will be updated to use a multi-select dropdown
*/

-- Create employee_stores junction table
CREATE TABLE IF NOT EXISTS employee_stores (
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (employee_id, store_id)
);

-- Migrate existing store assignments from employees.store_id to employee_stores
INSERT INTO employee_stores (employee_id, store_id)
SELECT id, store_id
FROM employees
WHERE store_id IS NOT NULL
ON CONFLICT (employee_id, store_id) DO NOTHING;

-- Enable RLS
ALTER TABLE employee_stores ENABLE ROW LEVEL SECURITY;

-- Policy: Authenticated users can view employee-store associations
CREATE POLICY "Authenticated users can view employee stores"
  ON employee_stores FOR SELECT
  TO authenticated
  USING (true);

-- Policy: Anonymous users can view employee-store associations
CREATE POLICY "Users can view own store associations"
  ON employee_stores FOR SELECT
  TO anon
  USING (true);

-- Policy: Admins can insert employee-store associations
CREATE POLICY "Admins can insert employee stores"
  ON employee_stores FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = auth.uid()
      AND employees.role_permission = 'Admin'
    )
  );

-- Policy: Admins can delete employee-store associations
CREATE POLICY "Admins can delete employee stores"
  ON employee_stores FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = auth.uid()
      AND employees.role_permission = 'Admin'
    )
  );

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_employee_stores_employee_id ON employee_stores(employee_id);
CREATE INDEX IF NOT EXISTS idx_employee_stores_store_id ON employee_stores(store_id);
