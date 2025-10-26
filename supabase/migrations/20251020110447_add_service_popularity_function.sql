/*
  # Add Service Popularity Sorting Function

  1. New Functions
    - `get_services_by_popularity` - Returns active services sorted by usage count
      - Counts total quantity of each service from ticket_items
      - Orders by usage count descending, then by service code ascending
      - Returns all service fields plus usage_count
  
  2. Purpose
    - Display most popular services first in the New Ticket modal
    - Help receptionists quickly find commonly used services
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