import React, { useState, useEffect } from 'react';
import { Calendar, Download, Printer, Plus, ChevronLeft, ChevronRight, Clock, CheckCircle, XCircle } from 'lucide-react';
import { supabase, Technician } from '../lib/supabase';
import { Button } from '../components/ui/Button';
import { useToast } from '../components/ui/Toast';
import { TicketEditor } from '../components/TicketEditor';
import { useAuth } from '../contexts/AuthContext';
import { Permissions } from '../lib/permissions';
import { WeeklyCalendarView } from '../components/WeeklyCalendarView';

interface AttendanceRecord {
  employee_id: string;
  employee_name: string;
  work_date: string;
  check_in_time: string;
  check_out_time?: string;
  total_hours?: number;
  status: string;
}

interface TechnicianSummary {
  technician_id: string;
  technician_name: string;
  services_count: number;
  revenue: number;
  tips_customer: number;
  tips_receptionist: number;
  tips_total: number;
  tips_cash: number;
  tips_card: number;
  items: ServiceItemDetail[];
}

interface ServiceItemDetail {
  ticket_id: string;
  service_code: string;
  service_name: string;
  price: number;
  tip_customer: number;
  tip_receptionist: number;
  tip_cash: number;
  tip_card: number;
  payment_method: string;
  opened_at: string;
  closed_at: string | null;
  duration_min: number;
}

interface EndOfDayPageProps {
  selectedDate: string;
  onDateChange: (date: string) => void;
}

export function EndOfDayPage({ selectedDate, onDateChange }: EndOfDayPageProps) {
  const [summaries, setSummaries] = useState<TechnicianSummary[]>([]);
  const [attendanceData, setAttendanceData] = useState<AttendanceRecord[]>([]);
  const [loading, setLoading] = useState(false);
  const [viewMode, setViewMode] = useState<'detail' | 'weekly'>('detail');
  const [weeklyData, setWeeklyData] = useState<Map<string, Map<string, { tips_cash: number; tips_card: number; tips_total: number }>>>(new Map());
  const { showToast } = useToast();
  const { session, selectedStoreId, t } = useAuth();

  const [totals, setTotals] = useState({
    tickets: 0,
    revenue: 0,
    tips: 0,
    tips_cash: 0,
    tips_card: 0,
  });

  const [isEditorOpen, setIsEditorOpen] = useState(false);
  const [editingTicketId, setEditingTicketId] = useState<string | null>(null);

  useEffect(() => {
    if (viewMode === 'weekly') {
      fetchWeeklyData();
    } else {
      fetchEODData();
    }
  }, [selectedDate, selectedStoreId, viewMode]);

  function getWeekStartDate(date: string): string {
    const d = new Date(date + 'T00:00:00');
    const day = d.getDay();
    const diff = day === 0 ? -6 : 1 - day;
    d.setDate(d.getDate() + diff);
    return d.toISOString().split('T')[0];
  }

  function getWeekDates(startDate: string): string[] {
    const dates: string[] = [];
    const d = new Date(startDate + 'T00:00:00');
    for (let i = 0; i < 7; i++) {
      dates.push(d.toISOString().split('T')[0]);
      d.setDate(d.getDate() + 1);
    }
    return dates;
  }

  async function fetchWeeklyData() {
    try {
      setLoading(true);

      const weekStart = getWeekStartDate(selectedDate);
      const weekDates = getWeekDates(weekStart);
      const weekEnd = weekDates[weekDates.length - 1];

      const canViewAll = session?.role_permission ? Permissions.endOfDay.canViewAll(session.role_permission) : false;
      const isTechnician = !canViewAll;

      let query = supabase
        .from('sale_tickets')
        .select(
          `
          id,
          ticket_date,
          ticket_items${isTechnician ? '!inner' : ''} (
            id,
            employee_id,
            tip_customer_cash,
            tip_customer_card,
            tip_receptionist,
            employee:employees!ticket_items_employee_id_fkey(
              id,
              display_name
            )
          )
        `
        )
        .gte('ticket_date', weekStart)
        .lte('ticket_date', weekEnd);

      if (selectedStoreId) {
        query = query.eq('store_id', selectedStoreId);
      }

      if (isTechnician && session?.employee_id) {
        query = query.eq('ticket_items.employee_id', session.employee_id);
      }

      const { data: tickets, error: ticketsError } = await query;

      if (ticketsError) throw ticketsError;

      const dataMap = new Map<string, Map<string, { tips_cash: number; tips_card: number; tips_total: number }>>();

      for (const ticket of tickets || []) {
        const ticketDate = (ticket as any).ticket_date;

        for (const item of (ticket as any).ticket_items || []) {
          const techId = item.employee_id;
          const technician = item.employee;

          if (!technician) continue;

          // Technicians should only see their own data
          if (isTechnician && session?.employee_id && techId !== session.employee_id) {
            continue;
          }

          if (!dataMap.has(techId)) {
            dataMap.set(techId, new Map());
          }

          const techMap = dataMap.get(techId)!;
          if (!techMap.has(ticketDate)) {
            techMap.set(ticketDate, { tips_cash: 0, tips_card: 0, tips_total: 0 });
          }

          const dayData = techMap.get(ticketDate)!;
          const tipCustomerCash = item.tip_customer_cash || 0;
          const tipCustomerCard = item.tip_customer_card || 0;
          const tipReceptionist = item.tip_receptionist || 0;
          const tipCash = tipCustomerCash + tipReceptionist;
          const tipCard = tipCustomerCard;
          const tipTotal = tipCash + tipCard;

          dayData.tips_cash += tipCash;
          dayData.tips_card += tipCard;
          dayData.tips_total += tipTotal;
        }
      }

      const techNames = new Map<string, string>();
      for (const ticket of tickets || []) {
        for (const item of (ticket as any).ticket_items || []) {
          if (item.employee) {
            techNames.set(item.employee_id, item.employee.display_name);
          }
        }
      }

      const sortedData = new Map(
        Array.from(dataMap.entries()).sort((a, b) => {
          const nameA = techNames.get(a[0]) || '';
          const nameB = techNames.get(b[0]) || '';
          return nameA.localeCompare(nameB);
        })
      );

      setWeeklyData(sortedData);

      const technicianMap = new Map<string, TechnicianSummary>();
      for (const [techId, dayMap] of sortedData.entries()) {
        const techName = techNames.get(techId) || 'Unknown';
        let totalCash = 0;
        let totalCard = 0;
        let totalTips = 0;

        for (const dayData of dayMap.values()) {
          totalCash += dayData.tips_cash;
          totalCard += dayData.tips_card;
          totalTips += dayData.tips_total;
        }

        technicianMap.set(techId, {
          technician_id: techId,
          technician_name: techName,
          services_count: 0,
          revenue: 0,
          tips_customer: 0,
          tips_receptionist: 0,
          tips_total: totalTips,
          tips_cash: totalCash,
          tips_card: totalCard,
          items: [],
        });
      }

      const sortedSummaries = Array.from(technicianMap.values());
      setSummaries(sortedSummaries);
    } catch (error) {
      showToast('Failed to load weekly data', 'error');
    } finally {
      setLoading(false);
    }
  }

  async function fetchAttendanceData() {
    if (!selectedStoreId) return;

    try {
      const isTechnician = session?.role_permission === 'Technician';

      const { data, error } = await supabase.rpc('get_store_attendance', {
        p_store_id: selectedStoreId,
        p_start_date: selectedDate,
        p_end_date: selectedDate,
        p_employee_id: isTechnician ? session?.employee_id : null
      });

      if (error) throw error;

      setAttendanceData(data || []);
    } catch (error) {
      console.error('Error fetching attendance:', error);
      showToast('Failed to load attendance data', 'error');
    }
  }

  async function fetchEODData() {
    try {
      setLoading(true);

      const canViewAll = session?.role_permission ? Permissions.endOfDay.canViewAll(session.role_permission) : false;
      const isTechnician = !canViewAll;

      let query = supabase
        .from('sale_tickets')
        .select(
          `
          id,
          total,
          payment_method,
          opened_at,
          closed_at,
          ticket_items${isTechnician ? '!inner' : ''} (
            id,
            service_id,
            employee_id,
            qty,
            price_each,
            addon_price,
            tip_customer_cash,
            tip_customer_card,
            tip_receptionist,
            service:services(code, name, duration_min),
            employee:employees!ticket_items_employee_id_fkey(
              id,
              display_name
            )
          )
        `
        )
        .eq('ticket_date', selectedDate);

      if (selectedStoreId) {
        query = query.eq('store_id', selectedStoreId);
      }

      if (isTechnician && session?.employee_id) {
        query = query.eq('ticket_items.employee_id', session.employee_id);
      }

      const { data: tickets, error: ticketsError } = await query;

      if (ticketsError) throw ticketsError;

      const technicianMap = new Map<string, TechnicianSummary>();
      let totalRevenue = 0;
      let totalTips = 0;
      let totalTipsCash = 0;
      let totalTipsCard = 0;

      for (const ticket of tickets || []) {
        totalRevenue += ticket.total;

        for (const item of (ticket as any).ticket_items || []) {
          const itemRevenue = (parseFloat(item.qty) || 0) * (parseFloat(item.price_each) || 0) + (parseFloat(item.addon_price) || 0);
          const techId = item.employee_id;
          const technician = item.employee;

          if (!technician) continue;

          // Technicians should only see their own data
          if (isTechnician && session?.employee_id && techId !== session.employee_id) {
            continue;
          }

          if (!technicianMap.has(techId)) {
            technicianMap.set(techId, {
              technician_id: techId,
              technician_name: technician.display_name,
              services_count: 0,
              revenue: 0,
              tips_customer: 0,
              tips_receptionist: 0,
              tips_total: 0,
              tips_cash: 0,
              tips_card: 0,
              items: [],
            });
          }

          const summary = technicianMap.get(techId)!;
          const tipCustomerCash = item.tip_customer_cash || 0;
          const tipCustomerCard = item.tip_customer_card || 0;
          const tipCustomer = tipCustomerCash + tipCustomerCard;
          const tipReceptionist = item.tip_receptionist || 0;
          const tipCash = tipCustomerCash + tipReceptionist;
          const tipCard = tipCustomerCard;

          summary.services_count += 1;
          summary.revenue += itemRevenue;
          summary.tips_customer += tipCustomer;
          summary.tips_receptionist += tipReceptionist;
          summary.tips_total += tipCustomer + tipReceptionist;
          summary.tips_cash += tipCash;
          summary.tips_card += tipCard;

          totalTips += tipCustomer + tipReceptionist;
          totalTipsCash += tipCash;
          totalTipsCard += tipCard;

          summary.items.push({
            ticket_id: ticket.id,
            service_code: item.service?.code || '',
            service_name: item.service?.name || '',
            price: itemRevenue,
            tip_customer: tipCustomer,
            tip_receptionist: tipReceptionist,
            tip_cash: tipCash,
            tip_card: tipCard,
            payment_method: (ticket as any).payment_method || '',
            opened_at: (ticket as any).opened_at,
            closed_at: ticket.closed_at,
            duration_min: item.service?.duration_min || 0,
          });
        }
      }

      let filteredSummaries = Array.from(technicianMap.values());

      // Sort items within each technician by opened_at (oldest first, recent at bottom)
      filteredSummaries.forEach(summary => {
        summary.items.sort((a, b) => {
          return new Date(a.opened_at).getTime() - new Date(b.opened_at).getTime();
        });
      });

      if (session?.role_permission === 'Technician') {
        filteredSummaries = filteredSummaries.filter(
          summary => summary.technician_id === session.employee_id
        );

        const technicianTotals = filteredSummaries[0];
        if (technicianTotals) {
          totalRevenue = technicianTotals.revenue;
          totalTips = technicianTotals.tips_total;
          totalTipsCash = technicianTotals.tips_cash;
          totalTipsCard = technicianTotals.tips_card;
        } else {
          totalRevenue = 0;
          totalTips = 0;
          totalTipsCash = 0;
          totalTipsCard = 0;
        }
      }

      setSummaries(filteredSummaries);
      setTotals({
        tickets: tickets?.length || 0,
        revenue: totalRevenue,
        tips: totalTips,
        tips_cash: totalTipsCash,
        tips_card: totalTipsCard,
      });
    } catch (error) {
      showToast('Failed to load EOD data', 'error');
    } finally {
      setLoading(false);
    }
  }

  function exportCSV() {
    // Technician Summary
    const techHeaders = [
      'Technician',
      'Services Done',
      'Revenue',
      'Tips (Customer)',
      'Tips (Receptionist)',
      'T. (Cash)',
      'T. (Card)',
      'Tips Total',
    ];

    const techRows = summaries.map((s) => [
      s.technician_name,
      s.services_count.toString(),
      s.revenue.toFixed(2),
      s.tips_customer.toFixed(2),
      s.tips_receptionist.toFixed(2),
      s.tips_cash.toFixed(2),
      s.tips_card.toFixed(2),
      s.tips_total.toFixed(2),
    ]);

    // Attendance Summary
    const attendanceHeaders = [
      'Employee',
      'Check In',
      'Check Out',
      'Hours',
      'Status',
    ];

    const attendanceRows = attendanceData.map((record) => [
      record.employee_name,
      new Date(record.check_in_time).toLocaleTimeString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
        hour12: true
      }),
      record.check_out_time
        ? new Date(record.check_out_time).toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
          })
        : '',
      record.total_hours ? record.total_hours.toFixed(2) : '',
      record.status,
    ]);

    const csv = [
      'Technician Summary',
      techHeaders.join(','),
      ...techRows.map(row => row.join(',')),
      '',
      'Attendance Summary',
      attendanceHeaders.join(','),
      ...attendanceRows.map(row => row.join(',')),
    ].join('\n');

    const blob = new Blob([csv], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `eod-report-${selectedDate}.csv`;
    a.click();
    window.URL.revokeObjectURL(url);

    showToast('End of Day Report exported successfully', 'success');
  }

  function handlePrint() {
    window.print();
    showToast('Opening print dialog', 'success');
  }

  function navigateWeek(direction: 'prev' | 'next') {
    const d = new Date(selectedDate);
    d.setDate(d.getDate() + (direction === 'prev' ? -7 : 7));
    onDateChange(d.toISOString().split('T')[0]);
  }

  function getCurrentWeekLabel(): string {
    const weekStart = getWeekStartDate(selectedDate);
    const weekDates = getWeekDates(weekStart);
    const startDate = new Date(weekDates[0]);
    const endDate = new Date(weekDates[6]);

    const formatDate = (d: Date) => `${d.getMonth() + 1}/${d.getDate()}`;
    return `${formatDate(startDate)} - ${formatDate(endDate)}`;
  }

  function getMinDate(): string {
    const date = new Date();
    date.setDate(date.getDate() - 7);
    return date.toISOString().split('T')[0];
  }

  function getMaxDate(): string {
    return new Date().toISOString().split('T')[0];
  }

  function openEditor(ticketId: string) {
    setEditingTicketId(ticketId);
    setIsEditorOpen(true);
  }

  function closeEditor() {
    setIsEditorOpen(false);
    setEditingTicketId(null);
    fetchEODData();
  }

  function openNewTicket() {
    setEditingTicketId(null);
    setIsEditorOpen(true);
  }

  function isTimeDeviationHigh(item: ServiceItemDetail): boolean {
    if (item.duration_min === 0) return false;

    const openedMs = new Date(item.opened_at).getTime();
    const closedMs = item.closed_at ? new Date(item.closed_at).getTime() : Date.now();
    const elapsedMinutes = Math.round((closedMs - openedMs) / 60000);

    // For open tickets: check if running 30% longer
    if (!item.closed_at) {
      return elapsedMinutes >= item.duration_min * 1.3;
    }

    // For closed tickets: check if 30% shorter OR 30% longer
    const tooFast = elapsedMinutes <= item.duration_min * 0.7;
    const tooSlow = elapsedMinutes >= item.duration_min * 1.3;

    return tooFast || tooSlow;
  }

  function processAttendanceData() {
    const summary: { [employeeId: string]: { employeeName: string; sessions: AttendanceRecord[] } } = {};

    attendanceData.forEach((record) => {
      if (!summary[record.employee_id]) {
        summary[record.employee_id] = {
          employeeName: record.employee_name,
          sessions: []
        };
      }
      summary[record.employee_id].sessions.push(record);
    });

    return Object.values(summary);
  }

  return (
    <div className="max-w-7xl mx-auto">
      <div className="mb-3 flex flex-col md:flex-row items-start md:items-center justify-between gap-2">
        <h2 className="text-base md:text-lg font-bold text-gray-900">{t('eod.title')}</h2>
        <div className="flex items-center gap-2 w-full md:w-auto flex-wrap">
          <div className="flex items-center gap-2 flex-1 md:flex-initial">
            <Calendar className="w-4 h-4 text-gray-400" />
            <input
              type="date"
              value={selectedDate}
              onChange={(e) => onDateChange(e.target.value)}
              min={getMinDate()}
              max={getMaxDate()}
              className="px-2 py-2 md:py-1 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 flex-1 md:flex-initial min-h-[44px] md:min-h-0"
            />
          </div>
          {session && session.role && Permissions.endOfDay.canExport(session.role) && (
            <>
              <Button variant="secondary" size="sm" onClick={exportCSV} className="hidden md:flex">
                <Download className="w-3 h-3 mr-1" />
                Export
              </Button>
              <Button variant="secondary" size="sm" onClick={handlePrint} className="hidden md:flex">
                <Printer className="w-3 h-3 mr-1" />
                Print
              </Button>
              <Button variant="primary" size="sm" onClick={openNewTicket} className="min-h-[44px] md:min-h-0">
                <Plus className="w-4 h-4 md:w-3 md:h-3 mr-1" />
                <span className="hidden xs:inline">New Ticket</span>
                <span className="xs:hidden">New</span>
              </Button>
            </>
          )}
        </div>
      </div>

      <div className="bg-white rounded-lg shadow mb-3">
        <div className="p-2 border-b border-gray-200 flex flex-col md:flex-row items-start md:items-center justify-between gap-2">
          <div className="flex items-center justify-between w-full md:w-auto">
            <h3 className="text-base font-semibold text-gray-900">Technician Summary</h3>
            {viewMode === 'weekly' && (
              <div className="flex items-center gap-2 md:hidden">
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => navigateWeek('prev')}
                >
                  <ChevronLeft className="w-4 h-4" />
                </Button>
                <span className="text-sm font-medium text-gray-700 min-w-[100px] text-center">
                  {getCurrentWeekLabel()}
                </span>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => navigateWeek('next')}
                >
                  <ChevronRight className="w-4 h-4" />
                </Button>
              </div>
            )}
          </div>
          <div className="flex gap-2 items-center w-full md:w-auto justify-between">
            {viewMode === 'weekly' && (
              <div className="hidden md:flex items-center gap-2">
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => navigateWeek('prev')}
                >
                  <ChevronLeft className="w-4 h-4" />
                </Button>
                <span className="text-sm font-medium text-gray-700 min-w-[120px] text-center">
                  {getCurrentWeekLabel()}
                </span>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => navigateWeek('next')}
                >
                  <ChevronRight className="w-4 h-4" />
                </Button>
              </div>
            )}
            <div className="flex gap-2">
            <Button
              size="sm"
              variant={viewMode === 'detail' ? 'primary' : 'ghost'}
              onClick={() => setViewMode('detail')}
            >
              Detail Grid
            </Button>
            <Button
              size="sm"
              variant={viewMode === 'weekly' ? 'primary' : 'ghost'}
              onClick={() => setViewMode('weekly')}
            >
              Weekly
            </Button>
            </div>
          </div>
        </div>

        {loading ? (
          <div className="flex items-center justify-center h-32">
            <div className="text-sm text-gray-500">Loading...</div>
          </div>
        ) : summaries.length === 0 ? (
          <div className="text-center py-8">
            <p className="text-sm text-gray-500">No tickets for this date</p>
          </div>
        ) : viewMode === 'weekly' ? (
          <div className="p-2 overflow-x-auto">
            <WeeklyCalendarView
              selectedDate={selectedDate}
              weeklyData={weeklyData}
              summaries={summaries}
            />
          </div>
        ) : (
          <div className="p-1 md:p-2 overflow-x-auto">
            <div className="flex gap-1 md:gap-1.5 min-w-max">
              {summaries.map((summary) => (
                <div
                  key={summary.technician_id}
                  className="flex-shrink-0 w-[130px] md:w-[9.5%] md:min-w-[90px] border border-gray-200 rounded-md bg-white shadow-sm"
                >
                  <div className="bg-gray-50 border-b border-gray-200 px-1.5 py-1 rounded-t-md">
                    <h4 className="text-[10px] font-semibold text-gray-900 leading-tight truncate">
                      {summary.technician_name}
                    </h4>
                    <p className="text-[9px] text-gray-500">
                      {summary.services_count} service{summary.services_count !== 1 ? 's' : ''}
                    </p>
                  </div>

                  <div className="p-1">
                    <div className="mb-1 pb-1 border-b border-gray-200 space-y-0.5">
                      <p className="text-[9px] font-medium text-gray-500 uppercase tracking-wide">
                        Summary
                      </p>
                      <div className="space-y-0.5">
                        <div className="flex justify-between items-center">
                          <span className="text-[9px] text-gray-600">T. (Cash)</span>
                          <span className="text-[9px] font-semibold text-green-600">
                            ${summary.tips_cash.toFixed(2)}
                          </span>
                        </div>
                        <div className="flex justify-between items-center">
                          <span className="text-[9px] text-gray-600">T. (Card)</span>
                          <span className="text-[9px] font-semibold text-blue-600">
                            ${summary.tips_card.toFixed(2)}
                          </span>
                        </div>
                        <div className="flex justify-between items-center pt-0.5 border-t border-gray-200">
                          <span className="text-[9px] font-medium text-gray-900">Total</span>
                          <span className="text-[10px] font-bold text-gray-900">
                            ${summary.tips_total.toFixed(2)}
                          </span>
                        </div>
                      </div>
                    </div>

                    <div>
                      <p className="text-[9px] font-medium text-gray-500 uppercase tracking-wide mb-0.5">
                        Sale Tickets
                      </p>
                      <div className="space-y-1 max-h-72 overflow-y-auto">
                        {summary.items.map((item, index) => {
                          const openTime = new Date(item.opened_at).toLocaleTimeString('en-US', {
                            hour: 'numeric',
                            minute: '2-digit',
                            hour12: true,
                          });
                          const openedMs = new Date(item.opened_at).getTime();
                          const closedMs = item.closed_at ? new Date(item.closed_at).getTime() : Date.now();
                          const durationMinutes = Math.round((closedMs - openedMs) / 60000);

                          const isOpen = !item.closed_at;
                          const hasTimeDeviation = isTimeDeviationHigh(item);

                          return (
                            <div
                              key={index}
                              className={`border rounded p-1 transition-colors cursor-pointer ${
                                hasTimeDeviation
                                  ? 'flash-red-border bg-red-50 hover:bg-red-100'
                                  : isOpen
                                  ? 'border-orange-300 bg-orange-50 hover:bg-orange-100'
                                  : 'border-gray-200 bg-gray-50 hover:bg-gray-100'
                              }`}
                              onClick={() => openEditor(item.ticket_id)}
                            >
                              <div className="mb-0.5">
                                <div className={`text-[8px] truncate mb-0.5 ${
                                  isOpen ? 'text-red-600 font-semibold' : 'text-gray-500'
                                }`}>
                                  {openTime.replace(/\s/g, '')} ({durationMinutes}m)
                                </div>
                                <div className="text-[9px] font-semibold text-gray-900">
                                  {item.service_code}
                                </div>
                              </div>
                              <div className="space-y-0">
                                <div className="flex justify-between items-center">
                                  <span className="text-[8px] text-gray-600">T. (given)</span>
                                  <span className={`text-[8px] font-semibold ${
                                    item.payment_method === 'Card' ? 'text-blue-600' : 'text-green-600'
                                  }`}>
                                    ${item.tip_customer.toFixed(2)}
                                  </span>
                                </div>
                                <div className="flex justify-between items-center">
                                  <span className="text-[8px] text-gray-600">T. (paired)</span>
                                  <span className="text-[8px] font-semibold text-green-600">
                                    ${item.tip_receptionist.toFixed(2)}
                                  </span>
                                </div>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Attendance Summary Section */}
      <div className="bg-white rounded-lg shadow mb-3">
        <div className="p-2 border-b border-gray-200">
          <h3 className="text-base font-semibold text-gray-900">Attendance Summary</h3>
        </div>
        {loading ? (
          <div className="flex items-center justify-center h-32">
            <div className="text-sm text-gray-500">Loading...</div>
          </div>
        ) : processAttendanceData().length === 0 ? (
          <div className="text-center py-8">
            <p className="text-sm text-gray-500">No attendance records for this date</p>
          </div>
        ) : (
          <div className="p-2 overflow-x-auto">
            <div className="flex gap-2 min-w-max">
              {processAttendanceData().map((employee) => (
                <div
                  key={employee.employeeName}
                  className="flex-shrink-0 w-[150px] border border-gray-200 rounded-md bg-white shadow-sm"
                >
                  <div className="bg-gray-50 border-b border-gray-200 px-2 py-1 rounded-t-md">
                    <h4 className="text-xs font-semibold text-gray-900 leading-tight truncate">
                      {employee.employeeName}
                    </h4>
                  </div>
                  <div className="p-2 space-y-1">
                    {employee.sessions.map((session, index) => (
                      <div key={index} className="border border-gray-200 rounded p-1 bg-gray-50">
                        <div className={`inline-flex items-center gap-1 px-1 py-0.5 rounded text-xs ${
                          session.status === 'checked_in'
                            ? 'bg-green-100 text-green-700'
                            : session.status === 'checked_out'
                            ? 'bg-gray-100 text-gray-700'
                            : 'bg-orange-100 text-orange-700'
                        }`}>
                          {session.status === 'checked_in' ? (
                            <Clock className="w-3 h-3" />
                          ) : session.status === 'checked_out' ? (
                            <CheckCircle className="w-3 h-3" />
                          ) : (
                            <XCircle className="w-3 h-3" />
                          )}
                          <span>{session.status === 'checked_in' ? 'In' : 'Out'}</span>
                        </div>
                        <div className="text-xs text-gray-600">
                          {new Date(session.check_in_time).toLocaleTimeString('en-US', {
                            hour: 'numeric',
                            minute: '2-digit',
                            hour12: true
                          })}
                        </div>
                        {session.check_out_time && (
                          <div className="text-xs text-gray-600">
                            {new Date(session.check_out_time).toLocaleTimeString('en-US', {
                              hour: 'numeric',
                              minute: '2-digit',
                              hour12: true
                            })}
                          </div>
                        )}
                        {session.total_hours && (
                          <div className="text-xs font-semibold text-gray-900">
                            {session.total_hours.toFixed(1)}h
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      {isEditorOpen && (
        <TicketEditor
          ticketId={editingTicketId}
          onClose={closeEditor}
          selectedDate={selectedDate}
        />
      )}
    </div>
  );
}
