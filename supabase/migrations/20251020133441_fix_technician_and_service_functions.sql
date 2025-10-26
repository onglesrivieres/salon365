/*
  # Fix Technician and Service Functions

  ## Overview
  Fixes type mismatches and query errors in the functions:
  - get_services_by_popularity: Change usage_count from bigint to numeric
  - get_sorted_technicians_for_store: Fix role check from array to text

  ## Changes
  1. get_services_by_popularity
     - Change return type of usage_count from bigint to numeric
     - Matches the actual SUM(qty) return type

  2. get_sorted_technicians_for_store
     - Change role check from array operator to simple equality
     - Matches the actual text column type
     - Use employee_stores junction table for multi-store support

  ## Security
  - Maintains existing search_path security
  - Uses STABLE qualifier for read-only operations
*/

-- Fix: Get services sorted by popularity (usage count)
DROP FUNCTION IF EXISTS get_services_by_popularity(uuid);
CREATE FUNCTION get_services_by_popularity(
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
  usage_count numeric
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

-- Fix: Get sorted technicians for ticket editor
DROP FUNCTION IF EXISTS get_sorted_technicians_for_store(uuid);
CREATE FUNCTION get_sorted_technicians_for_store(
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
    AND e.role = 'Technician'
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
