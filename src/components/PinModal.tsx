import { useState, useEffect, useRef } from 'react';
import { Modal } from './ui/Modal';
import { Lock } from 'lucide-react';

interface PinModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (pin: string) => void;
  title?: string;
  isLoading?: boolean;
  error?: string;
}

export function PinModal({ isOpen, onClose, onSubmit, title = 'Enter PIN', isLoading = false, error }: PinModalProps) {
  const [pin, setPin] = useState(['', '', '', '']);
  const inputRefs = [
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
  ];

  useEffect(() => {
    if (isOpen) {
      setPin(['', '', '', '']);
      setTimeout(() => inputRefs[0].current?.focus(), 100);
    }
  }, [isOpen]);

  useEffect(() => {
    if (error) {
      setPin(['', '', '', '']);
      setTimeout(() => inputRefs[0].current?.focus(), 100);
    }
  }, [error]);

  const handleChange = (index: number, value: string) => {
    if (!/^\d*$/.test(value)) return;

    const newPin = [...pin];
    newPin[index] = value.slice(-1);
    setPin(newPin);

    if (value && index < 3) {
      inputRefs[index + 1].current?.focus();
    }

    if (newPin.every(digit => digit !== '') && !isLoading) {
      const pinCode = newPin.join('');
      onSubmit(pinCode);
    }
  };

  const handleKeyDown = (index: number, e: React.KeyboardEvent) => {
    if (e.key === 'Backspace' && !pin[index] && index > 0) {
      inputRefs[index - 1].current?.focus();
    }
  };

  const handlePaste = (e: React.ClipboardEvent) => {
    e.preventDefault();
    const pastedData = e.clipboardData.getData('text').slice(0, 4);
    if (!/^\d+$/.test(pastedData)) return;

    const newPin = pastedData.split('').concat(['', '', '', '']).slice(0, 4);
    setPin(newPin);

    const nextEmptyIndex = newPin.findIndex(digit => !digit);
    if (nextEmptyIndex !== -1) {
      inputRefs[nextEmptyIndex].current?.focus();
    } else {
      inputRefs[3].current?.focus();
      if (!isLoading) {
        onSubmit(newPin.join(''));
      }
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={title}>
      <div className="text-center py-4">
        <div className="w-16 h-16 bg-blue-100 rounded-full flex items-center justify-center mx-auto mb-4">
          <Lock className="w-8 h-8 text-blue-600" />
        </div>

        <p className="text-gray-600 mb-6">Enter your 4-digit PIN</p>

        <div className="flex gap-3 justify-center mb-4">
          {pin.map((digit, index) => (
            <input
              key={index}
              ref={inputRefs[index]}
              type="password"
              inputMode="numeric"
              maxLength={1}
              value={digit}
              onChange={(e) => handleChange(index, e.target.value)}
              onKeyDown={(e) => handleKeyDown(index, e)}
              onPaste={handlePaste}
              disabled={isLoading}
              className="w-14 h-14 text-center text-2xl font-bold border-2 border-gray-300 rounded-lg focus:border-blue-600 focus:outline-none disabled:bg-gray-100 disabled:cursor-not-allowed"
            />
          ))}
        </div>

        {error && (
          <p className="text-red-600 text-sm mb-4">{error}</p>
        )}

        {isLoading && (
          <p className="text-gray-500 text-sm">Verifying...</p>
        )}

        <button
          onClick={onClose}
          disabled={isLoading}
          className="mt-4 px-6 py-2 text-gray-600 hover:text-gray-800 transition-colors disabled:opacity-50"
        >
          Cancel
        </button>
      </div>
    </Modal>
  );
}
