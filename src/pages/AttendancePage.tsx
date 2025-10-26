import { useState, useEffect } from 'react';
import { ChevronLeft, ChevronRight, Download, Clock, CheckCircle, XCircle, Users, MessageSquare } from 'lucide-react';
import { supabase, StoreAttendance } from '../lib/supabase';
import { Button } from '../components/ui/Button';
import { useToast } from '../components/ui/Toast';
import { useAuth } from '../contexts/AuthContext';
import { Permissions } from '../lib/permissions';
import { AttendanceCommentModal } from '../components/AttendanceCommentModal';

interface AttendanceSession {
  attendanceRecordId: string;
  checkInTime: string;
  checkOutTime?: string;
  totalHours?: number;
  status: string;
}

interface AttendanceSummary {
  [employeeId: string]: {
    employeeName: string;
    payType: string;
    dates: {
      [date: string]: AttendanceSession[];
    };
    totalHours: number;
    daysPresent: number;
  };
}

export function AttendancePage() {
  const [currentDate, setCurrentDate] = useState(new Date());
  const [attendanceData, setAttendanceData] = useState<StoreAttendance[]>([]);
  const [loading, setLoading] = useState(false);
  const [commentModalOpen, setCommentModalOpen] = useState(false);
  const [selectedAttendance, setSelectedAttendance] = useState<{
    employeeName: string;
    workDate: string;
    attendanceRecordId: string;
  } | null>(null);
  const { showToast } = useToast();
  const { session, selectedStoreId } = useAuth();

  useEffect(() => {
    if (selectedStoreId) {
      fetchAttendance();
    }
  }, [currentDate, selectedStoreId]);

  async function fetchAttendance() {
    if (!selectedStoreId) return;

    try {
      setLoading(true);
      const { startDate, endDate } = getDateRange();

      const isTechnician = session?.role_permission === 'Technician';

      const { data, error } = await supabase.rpc('get_store_attendance', {
        p_store_id: selectedStoreId,
        p_start_date: startDate,
        p_end_date: endDate,
        p_employee_id: isTechnician ? session?.employee_id : null
      });

      if (error) throw error;

      setAttendanceData(data || []);
    } catch (error: any) {
      console.error('Error fetching attendance:', error);
      showToast('Failed to load attendance data', 'error');
    } finally {
      setLoading(false);
    }
  }

  function getDateRange() {
    // Bi-weekly payroll periods starting from October 13, 2024 (Sunday)
    // This ensures periods align as: Oct 13-26, Oct 27-Nov 9, etc.
    // Which creates the pattern: Oct 12-25, Oct 26-Nov 8 for subsequent years
    const payrollStartDate = new Date(2024, 9, 13); // October 13, 2024

    // Normalize dates to midnight for accurate day calculation
    const normalizedCurrent = new Date(currentDate);
    normalizedCurrent.setHours(0, 0, 0, 0);

    const normalizedStart = new Date(payrollStartDate);
    normalizedStart.setHours(0, 0, 0, 0);

    const daysSinceStart = Math.floor((normalizedCurrent.getTime() - normalizedStart.getTime()) / (1000 * 60 * 60 * 24));
    const periodNumber = Math.floor(daysSinceStart / 14);

    const periodStart = new Date(normalizedStart);
    periodStart.setDate(periodStart.getDate() + (periodNumber * 14));

    const periodEnd = new Date(periodStart);
    periodEnd.setDate(periodEnd.getDate() + 13); // 14 days total (0-13)

    // Use local date formatting to avoid timezone conversion
    const formatLocalDate = (date: Date) => {
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      return `${year}-${month}-${day}`;
    };

    const startDate = formatLocalDate(periodStart);
    const endDate = formatLocalDate(periodEnd);
    return { startDate, endDate };
  }

  function getCalendarDays() {
    const { startDate, endDate } = getDateRange();

    // Parse dates properly to avoid timezone issues
    const [startYear, startMonth, startDay] = startDate.split('-').map(Number);
    const [endYear, endMonth, endDay] = endDate.split('-').map(Number);

    const start = new Date(startYear, startMonth - 1, startDay);
    const end = new Date(endYear, endMonth - 1, endDay);
    const days: Date[] = [];

    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      days.push(new Date(d));
    }

    return days;
  }

  function processAttendanceData(): AttendanceSummary {
    const summary: AttendanceSummary = {};

    attendanceData.forEach((record) => {
      if (!summary[record.employee_id]) {
        summary[record.employee_id] = {
          employeeName: record.employee_name,
          payType: record.pay_type,
          dates: {},
          totalHours: 0,
          daysPresent: 0
        };
      }

      if (!summary[record.employee_id].dates[record.work_date]) {
        summary[record.employee_id].dates[record.work_date] = [];
      }

      summary[record.employee_id].dates[record.work_date].push({
        attendanceRecordId: record.attendance_record_id,
        checkInTime: record.check_in_time,
        checkOutTime: record.check_out_time,
        totalHours: record.total_hours,
        status: record.status
      });

      if (record.total_hours) {
        summary[record.employee_id].totalHours += record.total_hours;
      }
    });

    // Calculate days present (unique dates)
    Object.values(summary).forEach(employee => {
      employee.daysPresent = Object.keys(employee.dates).length;
    });

    return summary;
  }

  function navigatePrevious() {
    const newDate = new Date(currentDate);
    newDate.setDate(newDate.getDate() - 14);
    setCurrentDate(newDate);
  }

  function navigateNext() {
    const newDate = new Date(currentDate);
    newDate.setDate(newDate.getDate() + 14);
    setCurrentDate(newDate);
  }

  function navigateToday() {
    setCurrentDate(new Date());
  }

  function exportCSV() {
    const summary = processAttendanceData();
    const { startDate, endDate } = getDateRange();

    const headers = ['Employee', 'Date', 'Check In', 'Check Out', 'Hours', 'Status'];
    const rows: string[][] = [];

    Object.values(summary).forEach((employee) => {
      Object.entries(employee.dates).forEach(([date, sessions]) => {
        sessions.forEach((record) => {
          const checkIn = new Date(record.checkInTime).toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
          });
          const checkOut = record.checkOutTime
            ? new Date(record.checkOutTime).toLocaleTimeString('en-US', {
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
              })
            : '';
          const hours = record.totalHours ? record.totalHours.toFixed(2) : '';

          rows.push([
            employee.employeeName,
          date,
          checkIn,
          checkOut,
          hours,
          record.status
          ]);
        });
      });
    });

    const csv = [headers, ...rows].map((row) => row.join(',')).join('\n');

    const blob = new Blob([csv], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `attendance-${startDate}-to-${endDate}.csv`;
    a.click();
    window.URL.revokeObjectURL(url);

    showToast('Attendance report exported successfully', 'success');
  }

  const calendarDays = getCalendarDays();
  const summary = processAttendanceData();
  const { startDate, endDate } = getDateRange();

  // Parse dates properly to avoid timezone issues
  const parseLocalDate = (dateStr: string) => {
    const [year, month, day] = dateStr.split('-').map(Number);
    return new Date(year, month - 1, day);
  };

  const periodRange = `${parseLocalDate(startDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} - ${parseLocalDate(endDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`;

  if (session && session.role && !Permissions.endOfDay.canView(session.role)) {
    return (
      <div className="max-w-7xl mx-auto">
        <div className="bg-white rounded-lg shadow p-8 text-center">
          <p className="text-gray-600">You don't have permission to view attendance records.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="w-full max-w-full mx-auto px-2">
      <div className="mb-2 flex flex-col md:flex-row items-start md:items-center justify-between gap-2">
        <h2 className="text-sm md:text-base font-bold text-gray-900">Attendance Tracking</h2>
        {session && session.role && Permissions.endOfDay.canExport(session.role) && (
          <Button variant="secondary" size="sm" onClick={exportCSV}>
            <Download className="w-3 h-3 mr-1" />
            Export
          </Button>
        )}
      </div>

      <div className="bg-white rounded-lg shadow mb-2">
        <div className="p-2 border-b border-gray-200 flex flex-col md:flex-row items-center justify-between gap-2">
          <div className="flex items-center gap-3">
            <Button variant="ghost" size="sm" onClick={navigatePrevious} className="min-h-[44px] md:min-h-0 min-w-[44px] md:min-w-0">
              <ChevronLeft className="w-5 h-5 md:w-4 md:h-4" />
            </Button>
            <h3 className="text-sm md:text-base font-semibold text-gray-900 min-w-[200px] text-center">
              {periodRange}
            </h3>
            <Button variant="ghost" size="sm" onClick={navigateNext} className="min-h-[44px] md:min-h-0 min-w-[44px] md:min-w-0">
              <ChevronRight className="w-5 h-5 md:w-4 md:h-4" />
            </Button>
          </div>
          <Button variant="secondary" size="sm" onClick={navigateToday} className="min-h-[44px] md:min-h-0 w-full md:w-auto">
            Today
          </Button>
        </div>

        {loading ? (
          <div className="flex items-center justify-center h-64">
            <div className="text-sm text-gray-500">Loading attendance data...</div>
          </div>
        ) : Object.keys(summary).length === 0 ? (
          <div className="text-center py-12">
            <Users className="w-12 h-12 text-gray-400 mx-auto mb-3" />
            <p className="text-sm text-gray-500">No attendance records for this period</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-gray-200">
                  <th className="text-left p-1.5 text-xs font-semibold text-gray-900 sticky left-0 bg-white z-10 min-w-[80px]">
                    Employee
                  </th>
                  {calendarDays.map((day, index) => {
                    const isToday = day.toDateString() === new Date().toDateString();
                    return (
                      <th
                        key={index}
                        className={`text-center p-1 text-xs font-semibold min-w-[60px] ${
                          isToday
                            ? 'bg-blue-50 text-blue-700'
                            : 'text-gray-900'
                        }`}
                      >
                        <div className="text-xs">{day.toLocaleDateString('en-US', { weekday: 'narrow' })}</div>
                        <div className="text-sm font-bold">{day.getDate()}</div>
                      </th>
                    );
                  })}
                  <th className="text-right p-1.5 text-xs font-semibold text-gray-900 sticky right-0 bg-white z-10 min-w-[60px]">
                    Total
                  </th>
                </tr>
              </thead>
              <tbody>
                {Object.entries(summary).map(([employeeId, employee]) => (
                  <tr key={employeeId} className="border-b border-gray-100 hover:bg-gray-50">
                    <td className="p-1.5 text-xs font-medium text-gray-900 sticky left-0 bg-white">
                      {employee.employeeName}
                    </td>
                    {calendarDays.map((day, index) => {
                      const dateStr = day.toISOString().split('T')[0];
                      const sessions = employee.dates[dateStr];
                      const isToday = day.toDateString() === new Date().toDateString();

                      return (
                        <td
                          key={index}
                          className={`p-0.5 text-center align-top ${
                            isToday ? 'bg-blue-50' : ''
                          }`}
                        >
                          {sessions && sessions.length > 0 ? (
                            <div className="space-y-1">
                              {sessions.map((record, sessionIdx) => (
                                <div key={sessionIdx} className="relative group border border-gray-200 rounded p-1">
                                  <div className="space-y-0.5">
                                    {sessions.length > 1 && (
                                      <div className="text-[10px] font-semibold text-gray-500">
                                        S{sessionIdx + 1}
                                      </div>
                                    )}
                                    <div className={`inline-flex items-center justify-center gap-0.5 px-1 py-0.5 rounded text-[10px] ${
                                      record.status === 'checked_in'
                                        ? 'bg-green-100 text-green-700'
                                        : record.status === 'checked_out'
                                        ? 'bg-gray-100 text-gray-700'
                                        : 'bg-orange-100 text-orange-700'
                                    }`}>
                                      {record.status === 'checked_in' ? (
                                        <Clock className="w-2 h-2" />
                                      ) : record.status === 'checked_out' ? (
                                        <CheckCircle className="w-2 h-2" />
                                      ) : (
                                        <XCircle className="w-2 h-2" />
                                      )}
                                      <span className="hidden sm:inline">{record.status === 'checked_in' ? 'In' : 'Out'}</span>
                                    </div>
                                    <div className="text-[10px] text-gray-600">
                                      {new Date(record.checkInTime).toLocaleTimeString('en-US', {
                                        hour: 'numeric',
                                        minute: '2-digit',
                                        hour12: false
                                      })}
                                    </div>
                                    {record.checkOutTime && (
                                      <div className="text-[10px] text-gray-600">
                                        {new Date(record.checkOutTime).toLocaleTimeString('en-US', {
                                          hour: 'numeric',
                                          minute: '2-digit',
                                          hour12: false
                                        })}
                                      </div>
                                    )}
                                    {record.totalHours && (
                                      <div className="text-[10px] font-semibold text-gray-900">
                                        {record.totalHours.toFixed(1)}h
                                      </div>
                                    )}
                                  </div>
                                  {session && session.role && Permissions.attendance.canComment(session.role) && (
                                    <button
                                      onClick={() => {
                                  setSelectedAttendance({
                                    employeeName: employee.employeeName,
                                    workDate: dateStr,
                                    attendanceRecordId: record.attendanceRecordId,
                                  });
                                  setCommentModalOpen(true);
                                      }}
                                      className="mt-0.5 opacity-0 group-hover:opacity-100 transition-opacity text-gray-400 hover:text-blue-600"
                                    >
                                      <MessageSquare className="w-3 h-3 mx-auto" />
                                    </button>
                                  )}
                                </div>
                              ))}
                            </div>
                          ) : (
                            <div className="text-gray-300">-</div>
                          )}
                        </td>
                      );
                    })}
                    <td className="p-1.5 text-right text-xs font-bold text-gray-900 sticky right-0 bg-white">
                      <div>{employee.totalHours.toFixed(1)}h</div>
                      <div className="text-[10px] font-normal text-gray-500">
                        {employee.daysPresent}d
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="bg-white rounded-lg shadow p-4">
        <h3 className="text-sm font-semibold text-gray-900 mb-3">Legend</h3>
        <div className="flex flex-wrap gap-4">
          <div className="flex items-center gap-2">
            <div className="flex items-center gap-2 px-2 py-1 rounded text-xs bg-green-100 text-green-700">
              <Clock className="w-3 h-3" />
              Active
            </div>
            <span className="text-xs text-gray-600">Currently checked in</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="flex items-center gap-2 px-2 py-1 rounded text-xs bg-gray-100 text-gray-700">
              <CheckCircle className="w-3 h-3" />
              Done
            </div>
            <span className="text-xs text-gray-600">Checked out</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="flex items-center gap-2 px-2 py-1 rounded text-xs bg-orange-100 text-orange-700">
              <XCircle className="w-3 h-3" />
              Done
            </div>
            <span className="text-xs text-gray-600">Auto checked out</span>
          </div>
        </div>
      </div>

      <AttendanceCommentModal
        isOpen={commentModalOpen}
        onClose={() => {
          setCommentModalOpen(false);
          setSelectedAttendance(null);
        }}
        employeeName={selectedAttendance?.employeeName || ''}
        workDate={selectedAttendance?.workDate || ''}
        attendanceRecordId={selectedAttendance?.attendanceRecordId || null}
      />
    </div>
  );
}
