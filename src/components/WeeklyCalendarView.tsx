import React from 'react';

interface WeeklyCalendarViewProps {
  selectedDate: string;
  weeklyData: Map<string, Map<string, { tips_cash: number; tips_card: number; tips_total: number }>>;
  summaries: Array<{
    technician_id: string;
    technician_name: string;
    tips_cash: number;
    tips_card: number;
    tips_total: number;
  }>;
}

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

function formatDateHeader(dateStr: string): { day: string; date: string } {
  const d = new Date(dateStr + 'T00:00:00');
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const day = days[d.getDay()];
  const date = `${d.getMonth() + 1}/${d.getDate()}`;
  return { day, date };
}

export function WeeklyCalendarView({ selectedDate, weeklyData, summaries }: WeeklyCalendarViewProps) {
  const weekStart = getWeekStartDate(selectedDate);
  const weekDates = getWeekDates(weekStart);

  return (
    <div className="overflow-x-auto -mx-4 sm:mx-0">
      <div className="inline-block min-w-full align-middle px-4 sm:px-0">
        <table className="min-w-full border-collapse text-xs">
          <thead>
            <tr>
              <th className="border border-gray-300 bg-gray-100 px-1.5 py-1 text-left font-semibold sticky left-0 z-10 w-20 sm:w-24">
                <div className="truncate">Tech</div>
              </th>
              {weekDates.map((date) => {
                const { day, date: dateStr } = formatDateHeader(date);
                return (
                  <th
                    key={date}
                    className="border border-gray-300 bg-gray-100 px-1 py-1 text-center font-semibold w-[72px] sm:w-20"
                  >
                    <div className="font-bold text-[10px] sm:text-xs">{day}</div>
                    <div className="text-[9px] sm:text-[10px] text-gray-600">{dateStr}</div>
                  </th>
                );
              })}
              <th className="border border-gray-300 bg-blue-100 px-1 py-1 text-center font-semibold w-[72px] sm:w-20">
                <div className="font-bold text-[10px] sm:text-xs">Total</div>
              </th>
            </tr>
          </thead>
          <tbody>
            {summaries.map((summary) => {
              const techData = weeklyData.get(summary.technician_id);

              return (
                <tr key={summary.technician_id}>
                  <td className="border border-gray-300 bg-gray-50 px-1.5 py-1 font-medium sticky left-0 z-10">
                    <div className="truncate text-[10px] sm:text-xs">{summary.technician_name}</div>
                  </td>
                  {weekDates.map((date) => {
                    const dayData = techData?.get(date);
                    const hasTips = dayData && dayData.tips_total > 0;

                    return (
                      <td
                        key={date}
                        className={`border border-gray-300 px-1 py-0.5 text-center ${
                          hasTips ? 'bg-white' : 'bg-gray-50'
                        }`}
                      >
                        {hasTips ? (
                          <div className="space-y-0.5">
                            <div className="flex flex-col items-center">
                              <span className="text-[9px] text-gray-500">Cash</span>
                              <span className="font-semibold text-green-600 text-[10px]">
                                ${dayData.tips_cash.toFixed(0)}
                              </span>
                            </div>
                            <div className="flex flex-col items-center">
                              <span className="text-[9px] text-gray-500">Card</span>
                              <span className="font-semibold text-blue-600 text-[10px]">
                                ${dayData.tips_card.toFixed(0)}
                              </span>
                            </div>
                            <div className="flex flex-col items-center pt-0.5 border-t border-gray-200">
                              <span className="font-bold text-gray-900 text-[11px]">
                                ${dayData.tips_total.toFixed(0)}
                              </span>
                            </div>
                          </div>
                        ) : (
                          <span className="text-gray-400 text-xs">-</span>
                        )}
                      </td>
                    );
                  })}
                  <td className="border border-gray-300 bg-blue-50 px-1 py-0.5 text-center">
                    <div className="space-y-0.5">
                      <div className="flex flex-col items-center">
                        <span className="text-[9px] text-gray-500">Cash</span>
                        <span className="font-semibold text-green-600 text-[10px]">
                          ${summary.tips_cash.toFixed(0)}
                        </span>
                      </div>
                      <div className="flex flex-col items-center">
                        <span className="text-[9px] text-gray-500">Card</span>
                        <span className="font-semibold text-blue-600 text-[10px]">
                          ${summary.tips_card.toFixed(0)}
                        </span>
                      </div>
                      <div className="flex flex-col items-center pt-0.5 border-t border-gray-900">
                        <span className="font-bold text-gray-900 text-[11px]">
                          ${summary.tips_total.toFixed(0)}
                        </span>
                      </div>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
