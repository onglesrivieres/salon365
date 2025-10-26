/*
  # Add Spa Expert Role

  1. Overview
    - Add a new role "Spa Expert" similar to "Technician"
    - Spa Experts can perform all services EXCEPT those in "Extensions des Ongles" category
    - They have same permissions as Technicians for tickets, attendance, approvals

  2. Changes
    - Employees can now have "Spa Expert" in their role array
    - Update functions to include Spa Expert where Technician is included
    - Add service category filtering logic for Spa Experts
*/

-- No schema changes needed to employees table since role is already an array
-- Just documenting that "Spa Expert" is now a valid role value

-- Note: The role filtering will be handled in the application layer
-- since we need to filter services by category which requires joining
-- with ticket_items and services tables dynamically
