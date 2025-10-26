/*
  # Add Approval Trigger and Backfill Existing Tickets

  ## Overview
  This migration:
  1. Creates the trigger function to set approval_deadline when tickets are closed
  2. Creates the trigger on sale_tickets table
  3. Backfills existing closed tickets with approval_status

  ## Trigger Function
  - Automatically sets approval_status to 'pending_approval' when a ticket is closed
  - Sets approval_deadline to closed_at + 48 hours
  - Only triggers when closed_at changes from NULL to a value

  ## Backfill Logic
  - Existing closed tickets get 'auto_approved' status (since they're already old)
  - Sets approved_at to closed_at for historical accuracy
*/

-- Create function to set approval deadline when ticket is closed
CREATE OR REPLACE FUNCTION set_approval_deadline()
RETURNS TRIGGER AS $$
BEGIN
  -- Only set approval fields when ticket is being closed
  IF NEW.closed_at IS NOT NULL AND (OLD.closed_at IS NULL OR OLD.closed_at IS DISTINCT FROM NEW.closed_at) THEN
    NEW.approval_status := 'pending_approval';
    NEW.approval_deadline := NEW.closed_at + INTERVAL '48 hours';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically set approval deadline
DROP TRIGGER IF EXISTS trigger_set_approval_deadline ON sale_tickets;
CREATE TRIGGER trigger_set_approval_deadline
  BEFORE UPDATE ON sale_tickets
  FOR EACH ROW
  EXECUTE FUNCTION set_approval_deadline();

-- Backfill existing closed tickets
-- Set them to 'auto_approved' since they're already closed and old
UPDATE sale_tickets
SET 
  approval_status = 'auto_approved',
  approved_at = closed_at,
  approval_deadline = closed_at + INTERVAL '48 hours'
WHERE closed_at IS NOT NULL
  AND approval_status IS NULL;