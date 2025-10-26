/*
  # Include Supervisors in Technician List

  ## Overview
  Updates get_sorted_technicians_for_store to include Supervisors in the technician dropdown.
  Since Supervisors have all Technician permissions, they should be available for 
  assignment to tickets.

  ## Changes
  - Update WHERE clause to check for Technician OR Supervisor role
  - Maintains all existing sorting and status logic

  ## Business Logic
  - Supervisors can perform technical work just like Technicians
  - They should appear in the technician selection dropdown
  - All queue logic applies to them the same way
*/

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
    -- Include both Technicians and Supervisors
    AND (e.role @> ARRAY['Technician']::text[] OR e.role @> ARRAY['Supervisor']::text[])
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