/*
  # Fix Security and Performance Issues

  ## Overview
  This migration addresses security and performance issues identified in the database:
  1. Adds missing indexes for foreign key columns to improve query performance
  2. Fixes function search paths to prevent security vulnerabilities

  ## Changes

  ### 1. Add Missing Foreign Key Indexes
  - `attendance_comments.employee_id` - For employee lookups
  - `sale_tickets.approved_by` - For approval tracking queries
  - `sale_tickets.closed_by` - For closed ticket queries
  - `sale_tickets.created_by` - For ticket creation tracking
  - `sale_tickets.saved_by` - For ticket modification tracking
  - `technician_ready_queue.current_open_ticket_id` - For queue status queries
  - `ticket_activity_log.employee_id` - For activity tracking by employee

  ### 2. Fix Function Search Paths
  All functions updated to use immutable search_path for security:
  - `verify_employee_pin`
  - `set_employee_pin`
  - `get_store_attendance`
  - `get_pending_approvals_for_technician`

  ## Security
  - Prevents search_path manipulation attacks
  - Improves query performance with proper indexing
  - Maintains existing RLS policies

  ## Notes
  - Unused index warnings are expected for new databases with minimal data
  - Indexes will be utilized as the database grows and queries are executed
*/

-- Add missing indexes for foreign key columns
CREATE INDEX IF NOT EXISTS idx_attendance_comments_employee_id 
  ON attendance_comments(employee_id);

CREATE INDEX IF NOT EXISTS idx_sale_tickets_approved_by 
  ON sale_tickets(approved_by);

CREATE INDEX IF NOT EXISTS idx_sale_tickets_closed_by 
  ON sale_tickets(closed_by);

CREATE INDEX IF NOT EXISTS idx_sale_tickets_created_by 
  ON sale_tickets(created_by);

CREATE INDEX IF NOT EXISTS idx_sale_tickets_saved_by 
  ON sale_tickets(saved_by);

CREATE INDEX IF NOT EXISTS idx_technician_ready_queue_current_open_ticket_id 
  ON technician_ready_queue(current_open_ticket_id);

CREATE INDEX IF NOT EXISTS idx_ticket_activity_log_employee_id 
  ON ticket_activity_log(employee_id);

-- Fix function search paths for security

-- Drop and recreate verify_employee_pin with fixed search_path
DROP FUNCTION IF EXISTS verify_employee_pin(uuid, text);
CREATE FUNCTION verify_employee_pin(
  p_employee_id uuid,
  p_pin_code text
)
RETURNS boolean 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_stored_hash text;
BEGIN
  SELECT pin_code_hash INTO v_stored_hash
  FROM employees
  WHERE id = p_employee_id;
  
  IF v_stored_hash IS NULL THEN
    RETURN false;
  END IF;
  
  RETURN v_stored_hash = crypt(p_pin_code, v_stored_hash);
END;
$$;

-- Drop and recreate set_employee_pin with fixed search_path
DROP FUNCTION IF EXISTS set_employee_pin(uuid, text);
CREATE FUNCTION set_employee_pin(
  p_employee_id uuid,
  p_pin_code text
)
RETURNS void 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE employees
  SET pin_code_hash = crypt(p_pin_code, gen_salt('bf')),
      last_pin_change = NOW(),
      pin_temp = NULL
  WHERE id = p_employee_id;
END;
$$;

-- Drop and recreate get_store_attendance with fixed search_path
DROP FUNCTION IF EXISTS get_store_attendance(uuid, date);
CREATE FUNCTION get_store_attendance(p_store_id uuid, p_work_date date)
RETURNS TABLE (
  attendance_record_id uuid,
  employee_id uuid,
  employee_name text,
  work_date date,
  check_in_time timestamptz,
  check_out_time timestamptz,
  total_hours numeric,
  status text,
  pay_type text
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ar.id as attendance_record_id,
    ar.employee_id,
    e.display_name as employee_name,
    ar.work_date,
    ar.check_in_time,
    ar.check_out_time,
    ar.total_hours,
    ar.status,
    ar.pay_type
  FROM attendance_records ar
  JOIN employees e ON ar.employee_id = e.id
  WHERE ar.store_id = p_store_id
    AND ar.work_date = p_work_date
  ORDER BY ar.check_in_time DESC;
END;
$$;

-- Drop and recreate get_pending_approvals_for_technician with fixed search_path
DROP FUNCTION IF EXISTS get_pending_approvals_for_technician(uuid, uuid);
CREATE FUNCTION get_pending_approvals_for_technician(
  p_employee_id uuid,
  p_store_id uuid
)
RETURNS TABLE (
  ticket_id uuid,
  ticket_no text,
  ticket_date date,
  closed_at timestamptz,
  approval_deadline timestamptz,
  customer_name text,
  customer_phone text,
  total numeric,
  closed_by_name text,
  hours_remaining numeric,
  service_name text,
  tip_customer numeric,
  tip_receptionist numeric,
  payment_method text
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    st.id as ticket_id,
    st.ticket_no,
    st.ticket_date,
    st.closed_at,
    st.approval_deadline,
    st.customer_name,
    st.customer_phone,
    st.total,
    COALESCE(e.display_name, 'Unknown') as closed_by_name,
    EXTRACT(EPOCH FROM (st.approval_deadline - NOW())) / 3600 as hours_remaining,
    s.name as service_name,
    ti.tip_customer,
    ti.tip_receptionist,
    st.payment_method
  FROM sale_tickets st
  LEFT JOIN employees e ON st.closed_by = e.id
  LEFT JOIN ticket_items ti ON ti.sale_ticket_id = st.id
  LEFT JOIN services s ON ti.service_id = s.id
  WHERE st.store_id = p_store_id
    AND st.approval_status = 'pending_approval'
    AND st.closed_at IS NOT NULL
    AND st.approval_deadline > NOW()
  ORDER BY st.approval_deadline ASC;
END;
$$;
