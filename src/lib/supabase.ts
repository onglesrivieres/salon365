import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Missing Supabase environment variables');
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
  global: {
    headers: {
      'x-application-name': 'salon360',
    },
  },
  db: {
    schema: 'public',
  },
  realtime: {
    params: {
      eventsPerSecond: 2,
    },
  },
});

export interface Store {
  id: string;
  name: string;
  code: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Technician {
  id: string;
  legal_name: string;
  display_name: string;
  role: ('Technician' | 'Receptionist' | 'Manager' | 'Owner' | 'Spa Expert' | 'Supervisor')[];
  role_permission?: 'Admin' | 'Receptionist' | 'Technician';
  status: 'Active' | 'Inactive';
  store_id?: string;
  pay_type?: 'hourly' | 'daily';
  payout_rule_type?: string;
  payout_commission_pct?: number;
  payout_hourly_rate?: number;
  payout_flat_per_service?: number;
  notes: string;
  pin_code_hash?: string;
  can_reset_pin?: boolean;
  pin_temp?: string;
  last_pin_change?: string;
  created_at: string;
  updated_at: string;
}

export type Employee = Technician;

export interface Service {
  id: string;
  code: string;
  name: string;
  base_price: number;
  duration_min: number;
  category: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface StoreService {
  id: string;
  store_id: string;
  service_id: string;
  price_override?: number;
  duration_override?: number;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface StoreServiceWithDetails {
  id: string;
  store_service_id: string;
  service_id: string;
  code: string;
  name: string;
  price: number;
  duration_min: number;
  category: string;
  active: boolean;
  created_at: string;
  updated_at: string;
  usage_count?: number;
}

export type ApprovalStatus = 'pending_approval' | 'approved' | 'rejected' | 'auto_approved';

export interface SaleTicket {
  id: string;
  ticket_no: string;
  store_id: string;
  ticket_date: string;
  opened_at: string;
  closed_at: string | null;
  completed_at?: string | null;
  completed_by?: string | null;
  customer_name: string;
  customer_phone: string;
  customer_type?: string;
  payment_method: 'Cash' | 'Card' | 'Mixed' | 'Other';
  discount: number;
  tax: number;
  total: number;
  location: string;
  notes: string;
  created_by?: string;
  saved_by?: string;
  closed_by?: string;
  approval_status?: ApprovalStatus | null;
  approved_at?: string | null;
  approved_by?: string | null;
  approval_deadline?: string | null;
  rejection_reason?: string | null;
  requires_admin_review?: boolean;
  created_at: string;
  updated_at: string;
}

export interface TicketItem {
  id: string;
  sale_ticket_id: string;
  service_id: string;
  employee_id: string;
  qty: number;
  price_each: number;
  addon_details?: string;
  addon_price?: number;
  tip_customer_cash: number;
  tip_customer_card: number;
  tip_receptionist: number;
  notes: string;
  created_at: string;
  updated_at: string;
}

export interface TicketItemWithDetails extends TicketItem {
  service?: Service;
  employee?: Technician;
}

export interface SaleTicketWithItems extends SaleTicket {
  ticket_items?: TicketItemWithDetails[];
}

export interface TicketActivityLog {
  id: string;
  ticket_id: string;
  employee_id?: string;
  action: 'created' | 'updated' | 'closed' | 'reopened' | 'approved' | 'rejected';
  description: string;
  changes?: Record<string, any>;
  created_at: string;
  employee?: Technician;
}

export interface TechnicianReadyQueue {
  id: string;
  employee_id: string;
  store_id: string;
  ready_at: string;
  status: 'ready' | 'busy';
  current_open_ticket_id?: string;
  created_at: string;
  updated_at: string;
}

export interface TechnicianWithQueue {
  employee_id: string;
  legal_name: string;
  display_name: string;
  queue_status: 'ready' | 'busy' | 'neutral';
  queue_position: number;
  ready_at?: string;
  current_open_ticket_id?: string;
  open_ticket_count: number;
  ticket_start_time?: string;
  estimated_duration_min?: number;
  estimated_completion_time?: string;
}

export interface AttendanceRecord {
  id: string;
  employee_id: string;
  store_id: string;
  work_date: string;
  check_in_time: string;
  check_out_time?: string;
  last_activity_time?: string;
  pay_type: 'hourly' | 'daily';
  status: 'checked_in' | 'checked_out' | 'auto_checked_out';
  total_hours?: number;
  notes: string;
  created_at: string;
  updated_at: string;
}

export interface AttendanceRecordWithEmployee extends AttendanceRecord {
  employee?: Technician;
}

export interface AttendanceSummary {
  work_date: string;
  check_in_time: string;
  check_out_time?: string;
  total_hours?: number;
  status: string;
  store_name: string;
}

export interface StoreAttendance {
  attendance_record_id: string;
  employee_id: string;
  employee_name: string;
  work_date: string;
  check_in_time: string;
  check_out_time?: string;
  total_hours?: number;
  status: string;
  pay_type: string;
}

export interface AttendanceComment {
  id: string;
  attendance_record_id: string;
  employee_id: string;
  comment: string;
  created_at: string;
  updated_at: string;
  employee?: Technician;
}

export interface PendingApprovalTicket {
  ticket_id: string;
  ticket_no: string;
  ticket_date: string;
  closed_at: string;
  approval_deadline: string;
  customer_name: string;
  customer_phone: string;
  total: number;
  closed_by_name: string;
  hours_remaining: number;
  service_name: string;
  tip_customer: number;
  tip_receptionist: number;
  payment_method: string;
  reason?: string;
  closed_by_roles?: any;
  requires_higher_approval?: boolean;
  technician_names?: string;
}

export interface ApprovalStatistics {
  total_closed: number;
  pending_approval: number;
  approved: number;
  auto_approved: number;
  rejected: number;
  requires_review: number;
}
