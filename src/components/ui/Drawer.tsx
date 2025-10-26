import React from 'react';
import { X } from 'lucide-react';

interface DrawerProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  position?: 'left' | 'right';
}

export function Drawer({ isOpen, onClose, title, children, position = 'right' }: DrawerProps) {
  if (!isOpen) return null;

  const positionStyles = position === 'right' ? 'right-0' : 'left-0';
  const slideAnimation = position === 'right' ? 'slide-in-right' : 'slide-in-left';

  return (
    <>
      <div
        className="fixed inset-0 bg-black bg-opacity-50 z-40 transition-opacity"
        onClick={onClose}
      />
      <div
        className={`fixed top-0 ${positionStyles} h-full w-full md:w-96 bg-white shadow-xl z-50 overflow-y-auto ${slideAnimation}`}
      >
        <div className="sticky top-0 bg-white border-b border-gray-200 px-6 py-4 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-gray-900">{title}</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors p-1"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        <div className="px-6 py-4">
          {children}
        </div>
      </div>
    </>
  );
}
