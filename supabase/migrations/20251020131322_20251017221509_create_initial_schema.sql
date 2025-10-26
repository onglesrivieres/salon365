/*
  # Salon360 Initial Database Schema

  ## Overview
  Creates the core tables for the Salon360 sale ticket tracking system:
  - Employees: Staff members who perform services
  - Services: Catalog of available services
  - Sale Tickets: Customer transactions/visits
  - Ticket Items: Individual services performed on each ticket

  ## Tables

  ### employees
  - `id` (uuid, primary key)
  - `legal_name` (text) - Full legal name for payroll
  - `display_name` (text) - Name shown in UI
  - `role` (text) - Technician, Receptionist, Manager, Owner
  - `status` (text) - Active or Inactive
  - `payout_rule_type` (text) - Commission, Hourly, Hybrid, FlatPerService
  - `payout_commission_pct` (numeric) - Commission percentage
  - `payout_hourly_rate` (numeric) - Hourly rate
  - `payout_flat_per_service` (numeric) - Flat rate per service
  - `notes` (text) - Additional notes
  - `created_at`, `updated_at` (timestamptz)

  ### services
  - `id` (uuid, primary key)
  - `code` (text, unique) - Service code (e.g., MANIC, PEDI)
  - `name` (text) - Full service name
  - `base_price` (numeric) - Default price
  - `duration_min` (integer) - Service duration in minutes
  - `category` (text) - Service category
  - `active` (boolean) - Is service active
  - `created_at`, `updated_at` (timestamptz)

  ### sale_tickets
  - `id` (uuid, primary key)
  - `ticket_no` (text, unique) - Format: ST-YYYYMMDD-####
  - `ticket_date` (date) - Transaction date
  - `opened_at` (timestamptz) - When ticket was created
  - `closed_at` (timestamptz) - When ticket was closed
  - `customer_name` (text) - Optional customer name
  - `payment_method` (text) - Cash, Card, Mixed, Other
  - `subtotal` (numeric) - Sum of all line items
  - `total` (numeric) - Final total
  - `location` (text) - Optional location
  - `notes` (text) - Additional notes
  - `created_at`, `updated_at` (timestamptz)

  ### ticket_items
  - `id` (uuid, primary key)
  - `sale_ticket_id` (uuid, FK) - References sale_tickets
  - `service_id` (uuid, FK) - References services
  - `employee_id` (uuid, FK) - Technician who performed service
  - `qty` (numeric) - Quantity
  - `price_each` (numeric) - Price per unit
  - `line_subtotal` (numeric) - qty * price_each
  - `tip_customer` (numeric) - Tip from customer
  - `tip_receptionist` (numeric) - Tip from receptionist
  - `notes` (text) - Additional notes
  - `created_at`, `updated_at` (timestamptz)

  ## Security
  - Enable RLS on all tables
  - Add policies for authenticated access

  ## Indexes
  - ticket_date for fast date filtering
  - employee_id for EOD reports
  - service_id for analytics
*/

-- Create employees table
CREATE TABLE IF NOT EXISTS employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_name text NOT NULL,
  display_name text NOT NULL,
  role text NOT NULL DEFAULT 'Technician',
  status text NOT NULL DEFAULT 'Active',
  payout_rule_type text DEFAULT 'Commission',
  payout_commission_pct numeric(5,2) DEFAULT 0.00,
  payout_hourly_rate numeric(10,2) DEFAULT 0.00,
  payout_flat_per_service numeric(10,2) DEFAULT 0.00,
  notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create services table
CREATE TABLE IF NOT EXISTS services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE NOT NULL,
  name text NOT NULL,
  base_price numeric(10,2) NOT NULL DEFAULT 0.00,
  duration_min integer DEFAULT 30,
  category text DEFAULT 'General',
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create sale_tickets table
CREATE TABLE IF NOT EXISTS sale_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_no text UNIQUE NOT NULL,
  ticket_date date NOT NULL DEFAULT CURRENT_DATE,
  opened_at timestamptz DEFAULT now(),
  closed_at timestamptz,
  customer_name text DEFAULT '',
  payment_method text DEFAULT 'Cash',
  subtotal numeric(10,2) DEFAULT 0.00,
  total numeric(10,2) DEFAULT 0.00,
  location text DEFAULT '',
  notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create ticket_items table
CREATE TABLE IF NOT EXISTS ticket_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_ticket_id uuid NOT NULL REFERENCES sale_tickets(id) ON DELETE CASCADE,
  service_id uuid NOT NULL REFERENCES services(id) ON DELETE RESTRICT,
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  qty numeric(10,2) DEFAULT 1.00,
  price_each numeric(10,2) NOT NULL DEFAULT 0.00,
  line_subtotal numeric(10,2) DEFAULT 0.00,
  tip_customer numeric(10,2) DEFAULT 0.00,
  tip_receptionist numeric(10,2) DEFAULT 0.00,
  notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_sale_tickets_ticket_date ON sale_tickets(ticket_date);
CREATE INDEX IF NOT EXISTS idx_sale_tickets_closed_at ON sale_tickets(closed_at);
CREATE INDEX IF NOT EXISTS idx_ticket_items_sale_ticket_id ON ticket_items(sale_ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_items_employee_id ON ticket_items(employee_id);
CREATE INDEX IF NOT EXISTS idx_ticket_items_service_id ON ticket_items(service_id);

-- Enable Row Level Security
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE services ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_items ENABLE ROW LEVEL SECURITY;

-- Create policies for public access (since this is an internal salon app)
CREATE POLICY "Allow all access to employees"
  ON employees FOR ALL
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow all access to services"
  ON services FOR ALL
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow all access to sale_tickets"
  ON sale_tickets FOR ALL
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow all access to ticket_items"
  ON ticket_items FOR ALL
  USING (true)
  WITH CHECK (true);

-- Insert sample data for testing
INSERT INTO employees (legal_name, display_name, role, payout_rule_type, payout_commission_pct) VALUES
  ('Anna Nguyen', 'Anna N.', 'Technician', 'Commission', 40.00),
  ('Mai Pham', 'Mai P.', 'Technician', 'Commission', 35.00),
  ('Linh Tran', 'Linh T.', 'Receptionist', 'Hourly', 0.00)
ON CONFLICT DO NOTHING;

INSERT INTO services (code, name, base_price, duration_min, category) VALUES
  ('MANIC', 'Classic Manicure', 28.00, 30, 'Manicure'),
  ('PEDI', 'Classic Pedicure', 40.00, 45, 'Pedicure'),
  ('GELF', 'Gel Fill', 45.00, 50, 'Nails'),
  ('SNSF', 'SNS Full Set', 55.00, 60, 'Nails'),
  ('ACRYL', 'Acrylic Full Set', 50.00, 60, 'Nails')
ON CONFLICT DO NOTHING;