/*
  # Backfill Existing Ticket Activities

  1. Changes
    - Create activity logs for all existing tickets
    - Log creation activities for all tickets based on their created_at timestamp
    - Log closure activities for closed tickets based on their closed_at timestamp

  2. Details
    - Uses created_by field if available, otherwise leaves employee_id as NULL
    - Creates 'created' action for all tickets
    - Creates 'closed' action for tickets with closed_at timestamp
*/

-- Insert creation activities for all existing tickets
INSERT INTO ticket_activity_log (ticket_id, employee_id, action, description, changes, created_at)
SELECT 
  id,
  created_by,
  'created',
  CASE 
    WHEN created_by IS NOT NULL THEN 'Ticket created'
    ELSE 'Ticket created (system migration)'
  END,
  jsonb_build_object(
    'ticket_no', ticket_no,
    'customer_name', customer_name,
    'total', total
  ),
  created_at
FROM sale_tickets
WHERE NOT EXISTS (
  SELECT 1 FROM ticket_activity_log 
  WHERE ticket_activity_log.ticket_id = sale_tickets.id 
  AND ticket_activity_log.action = 'created'
);

-- Insert closure activities for closed tickets
INSERT INTO ticket_activity_log (ticket_id, employee_id, action, description, changes, created_at)
SELECT 
  id,
  closed_by,
  'closed',
  CASE 
    WHEN closed_by IS NOT NULL THEN 'Ticket closed'
    ELSE 'Ticket closed (system migration)'
  END,
  jsonb_build_object(
    'total', total
  ),
  closed_at
FROM sale_tickets
WHERE closed_at IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM ticket_activity_log 
  WHERE ticket_activity_log.ticket_id = sale_tickets.id 
  AND ticket_activity_log.action = 'closed'
);