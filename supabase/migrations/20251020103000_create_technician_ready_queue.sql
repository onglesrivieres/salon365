/*
  # Create Technician Ready Queue System

  ## Overview
  Creates a queue management system for tracking technician availability and assignment order.
  When technicians click "Ready" on the Store Switcher page, they are added to a queue.
  The queue determines priority order for customer assignment in the New Ticket modal.

  ## New Tables

  ### technician_ready_queue
  - `id` (uuid, primary key) - Unique identifier
  - `employee_id` (uuid, foreign key) - References employees table
  - `store_id` (uuid, foreign key) - References stores table
  - `ready_at` (timestamptz) - When technician clicked Ready button
  - `status` (text) - Current status: 'ready' or 'busy'
  - `current_open_ticket_id` (uuid, nullable) - Current open ticket if busy
  - `created_at` (timestamptz) - Record creation timestamp
  - `updated_at` (timestamptz) - Last update timestamp

  ## Indexes
  - employee_id, store_id for fast lookups
  - ready_at for queue ordering
  - status for filtering

  ## Security
  - Enable RLS on technician_ready_queue table
  - Add policies for anonymous access (internal salon app)

  ## Functions
  - get_technician_queue_position: Calculate position in queue
  - mark_technician_busy: Update status when assigned to ticket
  - mark_technician_available: Update status when ticket closed
  - remove_from_ready_queue: Remove technician from queue
*/

-- Create technician_ready_queue table
CREATE TABLE IF NOT EXISTS technician_ready_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  store_id uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  ready_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'ready' CHECK (status IN ('ready', 'busy')),
  current_open_ticket_id uuid REFERENCES sale_tickets(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(employee_id, store_id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_technician_ready_queue_employee_id ON technician_ready_queue(employee_id);
CREATE INDEX IF NOT EXISTS idx_technician_ready_queue_store_id ON technician_ready_queue(store_id);
CREATE INDEX IF NOT EXISTS idx_technician_ready_queue_ready_at ON technician_ready_queue(ready_at);
CREATE INDEX IF NOT EXISTS idx_technician_ready_queue_status ON technician_ready_queue(status);

-- Enable Row Level Security
ALTER TABLE technician_ready_queue ENABLE ROW LEVEL SECURITY;

-- Create policy for anonymous access (internal salon app)
CREATE POLICY "Allow all access to technician_ready_queue"
  ON technician_ready_queue FOR ALL
  USING (true)
  WITH CHECK (true);

-- Function: Get technician's queue position
CREATE OR REPLACE FUNCTION get_technician_queue_position(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_position integer;
BEGIN
  SELECT COUNT(*) + 1 INTO v_position
  FROM technician_ready_queue
  WHERE store_id = p_store_id
    AND status = 'ready'
    AND ready_at < (
      SELECT ready_at
      FROM technician_ready_queue
      WHERE employee_id = p_employee_id
        AND store_id = p_store_id
    );

  RETURN COALESCE(v_position, 0);
END;
$$;

-- Function: Mark technician as busy when assigned to ticket
CREATE OR REPLACE FUNCTION mark_technician_busy(
  p_employee_id uuid,
  p_ticket_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE technician_ready_queue
  SET
    status = 'busy',
    current_open_ticket_id = p_ticket_id,
    updated_at = now()
  WHERE employee_id = p_employee_id
    AND status = 'ready';
END;
$$;

-- Function: Mark technician as available (remove from queue after ticket closed)
CREATE OR REPLACE FUNCTION mark_technician_available(
  p_employee_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM technician_ready_queue
  WHERE employee_id = p_employee_id;
END;
$$;

-- Function: Remove technician from ready queue (manual)
CREATE OR REPLACE FUNCTION remove_from_ready_queue(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM technician_ready_queue
  WHERE employee_id = p_employee_id
    AND store_id = p_store_id;
END;
$$;

-- Function: Clear entire queue for a store (manual reset)
CREATE OR REPLACE FUNCTION clear_store_ready_queue(
  p_store_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM technician_ready_queue
  WHERE store_id = p_store_id;
END;
$$;

-- Function: Get sorted technicians for ticket editor
CREATE OR REPLACE FUNCTION get_sorted_technicians_for_store(
  p_store_id uuid
)
RETURNS TABLE (
  employee_id uuid,
  legal_name text,
  display_name text,
  queue_status text,
  queue_position integer,
  ready_at timestamptz,
  current_open_ticket_id uuid,
  open_ticket_count integer
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH employee_open_tickets AS (
    SELECT
      ti.employee_id,
      COUNT(*) as ticket_count,
      MIN(st.opened_at) as oldest_ticket_at
    FROM ticket_items ti
    JOIN sale_tickets st ON ti.sale_ticket_id = st.id
    WHERE st.closed_at IS NULL
      AND st.store_id = p_store_id
    GROUP BY ti.employee_id
  ),
  queue_positions AS (
    SELECT
      trq.employee_id,
      trq.status,
      trq.ready_at,
      trq.current_open_ticket_id,
      ROW_NUMBER() OVER (ORDER BY trq.ready_at ASC) as position
    FROM technician_ready_queue trq
    WHERE trq.store_id = p_store_id
      AND trq.status = 'ready'
  )
  SELECT
    e.id as employee_id,
    e.legal_name,
    e.display_name,
    CASE
      WHEN eot.ticket_count > 0 THEN 'busy'
      WHEN qp.employee_id IS NOT NULL AND qp.status = 'ready' THEN 'ready'
      ELSE 'neutral'
    END as queue_status,
    COALESCE(qp.position::integer, 0) as queue_position,
    qp.ready_at,
    qp.current_open_ticket_id,
    COALESCE(eot.ticket_count::integer, 0) as open_ticket_count
  FROM employees e
  LEFT JOIN queue_positions qp ON e.id = qp.employee_id
  LEFT JOIN employee_open_tickets eot ON e.id = eot.employee_id
  WHERE e.status = 'Active'
    AND 'Technician' = ANY(e.role)
    AND (e.store_id IS NULL OR e.store_id = p_store_id)
  ORDER BY
    CASE
      WHEN eot.ticket_count > 0 THEN 3
      WHEN qp.employee_id IS NOT NULL AND qp.status = 'ready' THEN 1
      ELSE 2
    END,
    qp.ready_at ASC NULLS LAST,
    e.display_name ASC;
END;
$$;
