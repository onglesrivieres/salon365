/*
  # Fix Queue Position Numbering

  ## Issue
  The queue position was being calculated in the queue_positions CTE before filtering
  by employees who have access to the store. This caused positions to be incorrect:
  - If 2 technicians are in queue but only 1 has store access, that 1 shows as position 2
  - The ROW_NUMBER() was counting all queue entries, not just valid ones for the store

  ## Fix
  Recalculate the queue position AFTER filtering by store-assigned employees. This ensures:
  - Position 1 goes to the first available technician with store access
  - Position 2 goes to the second available technician with store access
  - And so on...

  ## Changes
  - Move the store assignment filter into the queue_positions CTE
  - This ensures ROW_NUMBER() only counts technicians who will actually be returned
  - Results in correct sequential numbering: 1, 2, 3, etc.
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
    JOIN employees e ON trq.employee_id = e.id
    WHERE trq.store_id = p_store_id
      AND trq.status = 'ready'
      AND LOWER(e.status) = 'active'
      AND (e.role @> ARRAY['Technician']::text[] OR e.role @> ARRAY['Supervisor']::text[])
      AND EXISTS (
        SELECT 1 FROM employee_stores es 
        WHERE es.employee_id = e.id 
        AND es.store_id = p_store_id
      )
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
  WHERE LOWER(e.status) = 'active'
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
