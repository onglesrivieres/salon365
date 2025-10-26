/*
  # Multi-Store POS Schema

  1. New Tables
    - `stores`
      - `id` (uuid, primary key)
      - `name` (text) - Store display name
      - `code` (text, unique) - Short code (e.g., "OM", "OC", "OR")
      - `active` (boolean, default true)
      - `created_at` (timestamptz)
      - `updated_at` (timestamptz)

    - `store_services`
      - `id` (uuid, primary key)
      - `store_id` (uuid, FK to stores)
      - `service_id` (uuid, FK to services)
      - `price_override` (numeric, optional)
      - `duration_override` (integer, optional)
      - `active` (boolean, default true)

  2. Modifications to Existing Tables
    - `employees`
      - Add `store_id` (FK to stores, optional) - Current assigned store
      - Add `default_store_id` (FK to stores, optional) - Preferred default store
      - Add payout fields:
        - `payout_rule_type` (text) - Rule type for commission calculation
        - `payout_commission_pct` (numeric, optional)
        - `payout_hourly_rate` (numeric, optional)
        - `payout_flat_per_service` (numeric, optional)

    - `sale_tickets`
      - Add `store_id` (uuid, FK to stores, required)
      - Add `opened_at` (timestamptz)
      - Add `closed_at` (timestamptz, optional)

  3. Security
    - Enable RLS on all new tables
    - Add policies for authenticated users with store-scoped access
*/

-- Create stores table
CREATE TABLE IF NOT EXISTS stores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  code text UNIQUE NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

ALTER TABLE stores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view active stores"
  ON stores FOR SELECT
  TO authenticated
  USING (active = true);

CREATE POLICY "Admin users can manage stores"
  ON stores FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = (current_setting('app.current_employee_id', true))::uuid
      AND employees.role_permission = 'Admin'
    )
  );

-- Add store-related columns to employees
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'store_id'
  ) THEN
    ALTER TABLE employees ADD COLUMN store_id uuid REFERENCES stores(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'default_store_id'
  ) THEN
    ALTER TABLE employees ADD COLUMN default_store_id uuid REFERENCES stores(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'payout_rule_type'
  ) THEN
    ALTER TABLE employees ADD COLUMN payout_rule_type text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'payout_commission_pct'
  ) THEN
    ALTER TABLE employees ADD COLUMN payout_commission_pct numeric;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'payout_hourly_rate'
  ) THEN
    ALTER TABLE employees ADD COLUMN payout_hourly_rate numeric;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'employees' AND column_name = 'payout_flat_per_service'
  ) THEN
    ALTER TABLE employees ADD COLUMN payout_flat_per_service numeric;
  END IF;
END $$;

-- Add store_id to sale_tickets
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'store_id'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN store_id uuid REFERENCES stores(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'opened_at'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN opened_at timestamptz DEFAULT now();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_tickets' AND column_name = 'closed_at'
  ) THEN
    ALTER TABLE sale_tickets ADD COLUMN closed_at timestamptz;
  END IF;
END $$;

-- Create store_services table for per-store service overrides
CREATE TABLE IF NOT EXISTS store_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  service_id uuid NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  price_override numeric,
  duration_override integer,
  active boolean DEFAULT true NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  UNIQUE(store_id, service_id)
);

ALTER TABLE store_services ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view store services"
  ON store_services FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admin and Receptionist can manage store services"
  ON store_services FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM employees
      WHERE employees.id = (current_setting('app.current_employee_id', true))::uuid
      AND employees.role_permission IN ('Admin', 'Receptionist')
    )
  );

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_employees_store_id ON employees(store_id);
CREATE INDEX IF NOT EXISTS idx_employees_default_store_id ON employees(default_store_id);
CREATE INDEX IF NOT EXISTS idx_sale_tickets_store_id ON sale_tickets(store_id);
CREATE INDEX IF NOT EXISTS idx_store_services_store_id ON store_services(store_id);
CREATE INDEX IF NOT EXISTS idx_store_services_service_id ON store_services(service_id);

-- Seed the 3 stores
INSERT INTO stores (name, code, active) VALUES
  ('Ongles Maily', 'OM', true),
  ('Ongles Charlesbourg', 'OC', true),
  ('Ongles Rivières', 'OR', true)
ON CONFLICT (code) DO NOTHING;
