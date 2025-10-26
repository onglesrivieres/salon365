/*
  # Update Service Popularity Function for Store-Specific Services

  ## Overview
  Modifies the get_services_by_popularity function to return store-specific services
  instead of global services, with proper price and duration overrides.

  ## Changes

  1. **Function Signature Update**
     - Make p_store_id parameter REQUIRED (non-nullable)
     - Function now queries store_services table
     - Joins with global services table for service details

  2. **Return Fields**
     - Returns store_services.id as the primary identifier
     - Returns service_id to maintain reference to global service
     - Returns price_override as the active price
     - Returns duration_override as the active duration
     - Includes all service metadata (code, name, category)
     - Maintains popularity sorting based on ticket usage

  ## Important Notes
  - All queries must now provide a valid store_id
  - Popularity is calculated based on store-specific ticket usage
  - Only active store_services entries are returned
*/

-- Drop the existing function
DROP FUNCTION IF EXISTS get_services_by_popularity(uuid);

-- Create updated function for store-specific services
CREATE OR REPLACE FUNCTION get_services_by_popularity(
  p_store_id uuid
)
RETURNS TABLE (
  id uuid,
  store_service_id uuid,
  service_id uuid,
  code text,
  name text,
  price numeric,
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
  -- Validate required parameter
  IF p_store_id IS NULL THEN
    RAISE EXCEPTION 'p_store_id parameter is required';
  END IF;

  RETURN QUERY
  WITH service_usage AS (
    SELECT
      ti.service_id,
      SUM(ti.qty) as total_usage
    FROM ticket_items ti
    JOIN sale_tickets st ON ti.sale_ticket_id = st.id
    WHERE st.store_id = p_store_id
    GROUP BY ti.service_id
  )
  SELECT
    s.id as id,
    ss.id as store_service_id,
    ss.service_id as service_id,
    s.code as code,
    s.name as name,
    COALESCE(ss.price_override, s.base_price) as price,
    COALESCE(ss.duration_override, s.duration_min) as duration_min,
    s.category as category,
    ss.active as active,
    ss.created_at as created_at,
    ss.updated_at as updated_at,
    COALESCE(su.total_usage, 0) as usage_count
  FROM store_services ss
  JOIN services s ON ss.service_id = s.id
  LEFT JOIN service_usage su ON ss.service_id = su.service_id
  WHERE ss.store_id = p_store_id
    AND ss.active = true
  ORDER BY
    COALESCE(su.total_usage, 0) DESC,
    s.code ASC;
END;
$$;

-- Add function comment
COMMENT ON FUNCTION get_services_by_popularity(uuid) IS 'Returns store-specific services sorted by popularity (usage count) within the specified store. Requires valid store_id parameter.';
