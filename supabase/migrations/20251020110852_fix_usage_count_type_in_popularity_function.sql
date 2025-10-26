/*
  # Fix Usage Count Type in Service Popularity Function

  1. Changes
    - Update `usage_count` return type from bigint to numeric
  
  2. Fix
    - qty column is numeric(10,2), so SUM(qty) returns numeric, not bigint
    - Change usage_count from bigint to numeric to match actual return type
*/

-- Drop and recreate the function with correct types
DROP FUNCTION IF EXISTS get_services_by_popularity(uuid);

CREATE OR REPLACE FUNCTION get_services_by_popularity(
  p_store_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  code text,
  name text,
  base_price numeric(10,2),
  duration_min integer,
  category text,
  active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  usage_count numeric
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