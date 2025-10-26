/*
  # Add Custom Service Support to Ticket Items

  1. Changes
    - Add `custom_service_name` text column to ticket_items table for custom service names
    - Make `service_id` nullable to support custom services that don't reference the services table
    - Add check constraint to ensure either service_id or custom_service_name is provided
  
  2. Security
    - No RLS changes needed, existing policies remain in effect
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ticket_items' AND column_name = 'custom_service_name'
  ) THEN
    ALTER TABLE ticket_items ADD COLUMN custom_service_name text;
  END IF;
END $$;

ALTER TABLE ticket_items ALTER COLUMN service_id DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE constraint_name = 'ticket_items_service_or_custom_check'
  ) THEN
    ALTER TABLE ticket_items
    ADD CONSTRAINT ticket_items_service_or_custom_check
    CHECK (
      (service_id IS NOT NULL AND custom_service_name IS NULL) OR
      (service_id IS NULL AND custom_service_name IS NOT NULL)
    );
  END IF;
END $$;
