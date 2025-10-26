import { RefreshCw } from 'lucide-react';

interface VersionNotificationProps {
  onRefresh: () => void;
}

export function VersionNotification({ onRefresh }: VersionNotificationProps) {
  return (
    <div className="fixed top-0 left-0 right-0 z-50 bg-blue-600 text-white shadow-lg animate-slideDown">
      <div className="container mx-auto px-4 py-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <RefreshCw className="w-5 h-5" />
          <span className="font-medium">A new version is available!</span>
        </div>
        <button
          onClick={onRefresh}
          className="px-4 py-2 bg-white text-blue-600 rounded-lg font-semibold hover:bg-blue-50 transition-colors flex items-center gap-2"
        >
          <RefreshCw className="w-4 h-4" />
          Refresh Now
        </button>
      </div>
    </div>
  );
}
