/*
  # Create Technician Queue and Sorting Functions

  ## Overview
  Creates missing database functions for the ticket editor:
  - get_sorted_technicians_for_store: Returns technicians sorted by queue status
  - get_services_by_popularity: Returns services sorted by usage count

  ## New Functions

  ### get_sorted_technicians_for_store
  Returns technicians with queue status and position for smart assignment:
  - Shows ready technicians first (in queue order)
  - Then neutral technicians (not in queue, no open tickets)
  - Finally busy technicians (with open tickets)

  ### get_services_by_popularity
  Returns services sorted by usage frequency:
  - Most used services appear first
  - Helps receptionists quickly find common services

  ## Security
  - Functions are accessible to all users (internal salon app)
  - Uses existing RLS policies on underlying tables
*/

-- Function: Get services sorted by popularity (usage count)
CREATE OR REPLACE FUNCTION get_services_by_popularity(
  p_store_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  code text,
  name text,
  base_price numeric,
  duration_min integer,
  category text,
  active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  usage_count bigint
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  WITH service_usage AS (
    SELECT
      ti.service_id,
      SUM(ti.qty) as total_usage
    FROM ticket_items ti
    JOIN sale_tickets st ON ti.sale_ticket_id = st.id
    WHERE (p_store_id IS NULL OR st.store_id = p_store_id)
    GROUP BY ti.service_id
  )
  SELECT
    s.id,
    s.code,
    s.name,
    s.base_price,
    s.duration_min,
    s.category,
    s.active,
    s.created_at,
    s.updated_at,
    COALESCE(su.total_usage, 0) as usage_count
  FROM services s
  LEFT JOIN service_usage su ON s.id = su.service_id
  WHERE s.active = true
  ORDER BY 
    COALESCE(su.total_usage, 0) DESC,
    s.code ASC;
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
STABLE
SET search_path = public, pg_temp
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
    AND EXISTS (
      SELECT 1 FROM employee_stores es 
      WHERE es.employee_id = e.id 
      AND es.store_id = p_store_id
    )
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
