/*
  # Clone Global Services to Store-Specific Services

  ## Overview
  This migration transitions the system from global services to store-specific services.
  Each store will have its own copy of all services with customizable prices and durations.

  ## Changes

  1. **Populate store_services Table**
     - Clone all active services from the global `services` table
     - Create entries for the single store (Sans Souci Ongles & Spa)
     - Inherit initial prices from global `base_price`
     - Inherit initial durations from global `duration_min`
     - Set all cloned services as active

  2. **Performance Indexes**
     - Add composite index on (store_id, active) for fast filtering
     - Add index on service_id for joins with global services table

  ## Important Notes
  - The global `services` table becomes a historical reference/template
  - Future service management happens through `store_services` table
  - Each store can now independently set prices and durations
  - Existing tickets remain valid as they reference global service_id
*/

-- Clone all active services to each store
INSERT INTO store_services (store_id, service_id, price_override, duration_override, active, created_at, updated_at)
SELECT
  stores.id as store_id,
  services.id as service_id,
  services.base_price as price_override,
  services.duration_min as duration_override,
  true as active,
  now() as created_at,
  now() as updated_at
FROM services
CROSS JOIN stores
WHERE services.active = true
  AND stores.active = true
ON CONFLICT (store_id, service_id) DO UPDATE
SET
  price_override = COALESCE(store_services.price_override, EXCLUDED.price_override),
  duration_override = COALESCE(store_services.duration_override, EXCLUDED.duration_override),
  updated_at = now();

-- Add composite index for efficient store-scoped queries
CREATE INDEX IF NOT EXISTS idx_store_services_store_active
  ON store_services(store_id, active);

-- Add index for service joins
CREATE INDEX IF NOT EXISTS idx_store_services_service_lookup
  ON store_services(service_id)
  WHERE active = true;

-- Add comment to services table indicating its new role
COMMENT ON TABLE services IS 'Service catalog template - serves as historical reference. Active service management happens through store_services table.';
