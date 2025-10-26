import React, { useState } from 'react';
import { Lock, Delete, ArrowLeft } from 'lucide-react';
import { authenticateWithPIN } from '../lib/auth';
import { useAuth } from '../contexts/AuthContext';
import { useToast } from '../components/ui/Toast';
import { supabase } from '../lib/supabase';

interface LoginPageProps {
  selectedAction?: 'checkin' | 'ready' | 'report' | null;
  onCheckOutComplete?: () => void;
  onBack?: () => void;
}

export function LoginPage({ selectedAction, onCheckOutComplete, onBack }: LoginPageProps) {
  const [pin, setPin] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const { login, t, selectedStoreId } = useAuth();
  const { showToast } = useToast();

  const handleNumberClick = async (num: string) => {
    if (pin.length < 4) {
      const newPin = pin + num;
      setPin(newPin);

      if (newPin.length === 4) {
        await submitPIN(newPin);
      }
    }
  };

  const submitPIN = async (pinToSubmit: string) => {
    setIsLoading(true);

    try {
      const session = await authenticateWithPIN(pinToSubmit);

      if (session) {
        if (selectedAction === 'checkin') {
          await handleCheckInOut(session);
        } else if (selectedAction === 'ready') {
          login(session);
        } else {
          login(session);
        }
      } else {
        showToast(t('auth.invalidPIN'), 'error');
        setPin('');
      }
    } catch (error) {
      showToast(t('auth.invalidPIN'), 'error');
      setPin('');
    } finally {
      setIsLoading(false);
    }
  };

  const handleCheckInOut = async (session: any) => {
    let storeId = selectedStoreId || sessionStorage.getItem('selected_store_id');

    if (!storeId) {
      const today = new Date().toISOString().split('T')[0];
      const { data: attendanceRecord } = await supabase
        .from('attendance_records')
        .select('store_id')
        .eq('employee_id', session.employee_id)
        .eq('work_date', today)
        .eq('status', 'checked_in')
        .maybeSingle();

      if (attendanceRecord) {
        storeId = attendanceRecord.store_id;
      } else {
        const { data: employeeStores } = await supabase
          .from('employee_stores')
          .select('store_id')
          .eq('employee_id', session.employee_id)
          .limit(1)
          .maybeSingle();

        if (employeeStores) {
          storeId = employeeStores.store_id;
        }
      }
    }

    if (!storeId) {
      showToast('No store found for check-in/out', 'error');
      return;
    }

    try {
      const { data: employee, error: empError } = await supabase
        .from('employees')
        .select('pay_type, display_name')
        .eq('id', session.employee_id)
        .maybeSingle();

      if (empError) throw empError;

      const payType = employee?.pay_type || 'hourly';
      const displayName = employee?.display_name || session.display_name || 'Employee';

      if (payType === 'daily') {
        showToast(`${displayName}, you don't need to check in/out. You're paid daily!`, 'info');
        return;
      }

      const today = new Date().toISOString().split('T')[0];
      const { data: attendance } = await supabase
        .from('attendance_records')
        .select('*')
        .eq('employee_id', session.employee_id)
        .eq('store_id', storeId)
        .eq('work_date', today)
        .maybeSingle();

      const isCheckedIn = attendance && attendance.status === 'checked_in';

      if (!isCheckedIn) {
        const { error: checkInError } = await supabase.rpc('check_in_employee', {
          p_employee_id: session.employee_id,
          p_store_id: storeId,
          p_pay_type: payType
        });

        if (checkInError) throw checkInError;

        const { error: queueError } = await supabase.rpc('join_ready_queue', {
          p_employee_id: session.employee_id,
          p_store_id: storeId
        });

        if (queueError) console.error('Failed to join queue:', queueError);

        showToast(`Welcome ${displayName}! You're checked in and in the ready queue.`, 'success');
        login(session);
      } else {
        const { data: checkOutSuccess, error: checkOutError } = await supabase.rpc('check_out_employee', {
          p_employee_id: session.employee_id,
          p_store_id: storeId
        });

        if (checkOutError) throw checkOutError;

        if (!checkOutSuccess) {
          showToast('No active check-in found', 'error');
          return;
        }

        const { error: deleteError } = await supabase
          .from('technician_ready_queue')
          .delete()
          .eq('employee_id', session.employee_id)
          .eq('store_id', storeId);

        if (deleteError) {
          console.error('Failed to remove from queue:', deleteError);
        }

        showToast(`Goodbye ${displayName}! You've been checked out. See you soon!`, 'success');
        console.log(`${displayName} checked out and removed from queue`);

        setTimeout(() => {
          if (onCheckOutComplete) {
            onCheckOutComplete();
          }
        }, 2000);
      }
    } catch (error: any) {
      console.error('Check-in/out failed:', error);
      showToast('Check-in/out failed. Please try again.', 'error');
    }
  };

  const handleClear = () => {
    setPin('');
  };

  const handleKeyPress = async (e: React.KeyboardEvent) => {
    if (e.key >= '0' && e.key <= '9' && pin.length < 4) {
      const newPin = pin + e.key;
      setPin(newPin);

      if (newPin.length === 4) {
        await submitPIN(newPin);
      }
    } else if (e.key === 'Backspace') {
      setPin(pin.slice(0, -1));
    }
  };

  return (
    <div
      className="min-h-screen bg-gradient-to-br from-blue-50 to-blue-100 flex items-center justify-center p-4"
      onKeyDown={handleKeyPress}
      tabIndex={0}
    >
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-blue-600 rounded-full mb-4">
            <Lock className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-3xl font-bold text-gray-900 mb-2">Salon360</h1>
          <p className="text-gray-600">{t('auth.enterPIN')}</p>
        </div>

        <div className="bg-white rounded-2xl shadow-xl p-8">
          <div className="mb-8">
            <div className="flex justify-center gap-3 mb-2">
              {[0, 1, 2, 3].map((i) => (
                <div
                  key={i}
                  className={`w-14 h-14 rounded-full border-2 flex items-center justify-center transition-all duration-200 ${
                    pin.length > i
                      ? 'border-blue-600 bg-blue-50'
                      : 'border-gray-300 bg-white'
                  }`}
                >
                  {pin.length > i && (
                    <div className="w-3 h-3 bg-blue-600 rounded-full animate-pulse"></div>
                  )}
                </div>
              ))}
            </div>
            <p className="text-center text-xs text-gray-500 mt-2">
              {pin.length}/4 {t('auth.digitsEntered')}
            </p>
          </div>

          <div className="grid grid-cols-3 gap-3 mb-4">
            {['1', '2', '3', '4', '5', '6'].map((num) => (
              <button
                key={num}
                onClick={() => handleNumberClick(num)}
                disabled={isLoading}
                className="h-16 bg-gray-50 hover:bg-gray-100 active:bg-gray-200 rounded-xl text-2xl font-semibold text-gray-900 transition-all duration-150 transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed shadow-sm"
              >
                {num}
              </button>
            ))}
            <button
              onClick={() => handleNumberClick('7')}
              disabled={isLoading}
              className="h-16 bg-gray-50 hover:bg-gray-100 active:bg-gray-200 rounded-xl text-2xl font-semibold text-gray-900 transition-all duration-150 transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed shadow-sm"
            >
              7
            </button>
            <button
              onClick={() => handleNumberClick('8')}
              disabled={isLoading}
              className="h-16 bg-gray-50 hover:bg-gray-100 active:bg-gray-200 rounded-xl text-2xl font-semibold text-gray-900 transition-all duration-150 transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed shadow-sm"
            >
              8
            </button>
            <button
              onClick={() => handleNumberClick('9')}
              disabled={isLoading}
              className="h-16 bg-gray-50 hover:bg-gray-100 active:bg-gray-200 rounded-xl text-2xl font-semibold text-gray-900 transition-all duration-150 transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed shadow-sm"
            >
              9
            </button>
            {onBack ? (
              <button
                onClick={onBack}
                disabled={isLoading}
                className="h-16 bg-gray-50 hover:bg-gray-100 active:bg-gray-200 rounded-xl text-sm font-medium text-gray-700 transition-all duration-150 transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed shadow-sm flex items-center justify-center gap-2"
              >
                <ArrowLeft className="w-4 h-4" />
                {t('actions.back')}
              </button>
            ) : (
              <div className="h-16"></div>
            )}
            <button
              onClick={() => handleNumberClick('0')}
              disabled={isLoading}
              className="h-16 bg-gray-50 hover:bg-gray-100 active:bg-gray-200 rounded-xl text-2xl font-semibold text-gray-900 transition-all duration-150 transform active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed shadow-sm"
            >
              0
            </button>
            <button
              onClick={handleClear}
              disabled={isLoading || pin.length === 0}
              className="h-16 bg-red-50 hover:bg-red-100 active:bg-red-200 rounded-xl text-sm font-medium text-red-700 transition-all duration-150 transform active:scale-95 disabled:opacity-30 disabled:cursor-not-allowed shadow-sm flex items-center justify-center gap-1"
            >
              <Delete className="w-4 h-4" />
              {t('actions.reset')}
            </button>
          </div>

          {isLoading && (
            <div className="text-center text-sm text-blue-600 font-medium">
              {t('messages.loading')}
            </div>
          )}
          {!isLoading && (
            <div className="text-center text-xs text-gray-500 mt-4">
              <p>{t('auth.autoSubmit')}</p>
            </div>
          )}
        </div>

        <div className="text-center mt-6 text-sm text-gray-600">
          <p>{t('auth.forgotPIN')}</p>
        </div>
      </div>
    </div>
  );
}
