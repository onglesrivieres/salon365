const EST_TIMEZONE = 'America/New_York';

export function formatTimeEST(date: Date | string, options?: Intl.DateTimeFormatOptions): string {
  const dateObj = typeof date === 'string' ? new Date(date) : date;

  const defaultOptions: Intl.DateTimeFormatOptions = {
    timeZone: EST_TIMEZONE,
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
    ...options
  };

  return dateObj.toLocaleTimeString('en-US', defaultOptions);
}

export function formatDateEST(date: Date | string, options?: Intl.DateTimeFormatOptions): string {
  const dateObj = typeof date === 'string' ? new Date(date) : date;

  const defaultOptions: Intl.DateTimeFormatOptions = {
    timeZone: EST_TIMEZONE,
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    ...options
  };

  return dateObj.toLocaleDateString('en-US', defaultOptions);
}

export function formatDateTimeEST(date: Date | string, options?: Intl.DateTimeFormatOptions): string {
  const dateObj = typeof date === 'string' ? new Date(date) : date;

  const defaultOptions: Intl.DateTimeFormatOptions = {
    timeZone: EST_TIMEZONE,
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
    ...options
  };

  return dateObj.toLocaleString('en-US', defaultOptions);
}

export function getCurrentDateEST(): string {
  const now = new Date();
  const estDate = new Date(now.toLocaleString('en-US', { timeZone: EST_TIMEZONE }));
  const year = estDate.getFullYear();
  const month = String(estDate.getMonth() + 1).padStart(2, '0');
  const day = String(estDate.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function getESTTimezone(): string {
  return EST_TIMEZONE;
}
