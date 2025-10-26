/*
  # Add Estimated Completion Time for Busy Technicians

  1. Changes
    - Update `get_sorted_technicians_for_store` function to include:
      - `ticket_start_time` (timestamptz) - When the open ticket was started
      - `estimated_duration_min` (integer) - Total estimated service duration in minutes
      - `estimated_completion_time` (timestamptz) - Calculated completion time
    
  2. Purpose
    - Display estimated wait time for busy technicians in the New Ticket modal
    - Calculate time remaining based on service duration minus elapsed time
*/

-- Drop existing function
DROP FUNCTION IF EXISTS get_sorted_technicians_for_store(uuid);

-- Recreate with additional fields
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
  open_ticket_count integer,
  ticket_start_time timestamptz,
  estimated_duration_min integer,
  estimated_completion_time timestamptz
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH employee_open_tickets AS (
    SELECT
      ti.employee_id,
      COUNT(DISTINCT st.id) as ticket_count,
      MIN(st.opened_at) as oldest_ticket_at,
      SUM(s.duration_min * ti.qty) as total_duration_min
    FROM ticket_items ti
    JOIN sale_tickets st ON ti.sale_ticket_id = st.id
    JOIN services s ON ti.service_id = s.id
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
    COALESCE(eot.ticket_count::integer, 0) as open_ticket_count,
    eot.oldest_ticket_at as ticket_start_time,
    COALESCE(eot.total_duration_min::integer, 0) as estimated_duration_min,
    CASE
      WHEN eot.oldest_ticket_at IS NOT NULL AND eot.total_duration_min IS NOT NULL 
      THEN eot.oldest_ticket_at + (eot.total_duration_min || ' minutes')::interval
      ELSE NULL
    END as estimated_completion_time
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