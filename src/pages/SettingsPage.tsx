import React, { useState } from 'react';
import { Key, AlertCircle } from 'lucide-react';
import { Button } from '../components/ui/Button';
import { useToast } from '../components/ui/Toast';
import { useAuth } from '../contexts/AuthContext';
import { changePIN } from '../lib/auth';

export function SettingsPage() {
  const { showToast } = useToast();
  const { session } = useAuth();

  const [oldPIN, setOldPIN] = useState('');
  const [newPIN, setNewPIN] = useState('');
  const [confirmPIN, setConfirmPIN] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleChangePIN(e: React.FormEvent) {
    e.preventDefault();

    if (!/^\d{4}$/.test(oldPIN)) {
      showToast('Current PIN must be 4 digits', 'error');
      return;
    }

    if (!/^\d{4}$/.test(newPIN)) {
      showToast('New PIN must be 4 digits', 'error');
      return;
    }

    if (newPIN !== confirmPIN) {
      showToast('New PINs do not match', 'error');
      return;
    }

    if (oldPIN === newPIN) {
      showToast('New PIN must be different from current PIN', 'error');
      return;
    }

    if (!session) {
      showToast('Session expired', 'error');
      return;
    }

    setIsSubmitting(true);

    try {
      const result = await changePIN(session.employee_id, oldPIN, newPIN);

      if (result.success) {
        showToast('PIN changed successfully', 'success');
        setOldPIN('');
        setNewPIN('');
        setConfirmPIN('');
      } else {
        showToast(result.error || 'Failed to change PIN', 'error');
      }
    } catch (error) {
      showToast('An error occurred', 'error');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="max-w-7xl mx-auto">
      <div className="mb-4">
        <h2 className="text-lg font-bold text-gray-900 mb-3">Settings</h2>
      </div>

      <div className="max-w-2xl">
        <div className="mb-4">
            <p className="text-sm text-gray-600">
              Update your 4-digit PIN for accessing the system
            </p>
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-start gap-3 mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
              <AlertCircle className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
              <div className="text-sm text-blue-800">
                <p className="font-medium mb-1">Security Tips</p>
                <ul className="list-disc list-inside space-y-1 text-xs">
                  <li>Choose a PIN that is easy for you to remember but hard for others to guess</li>
                  <li>Do not use obvious combinations like 1234 or 0000</li>
                  <li>Do not share your PIN with anyone</li>
                  <li>Change your PIN regularly for better security</li>
                </ul>
              </div>
            </div>

            <form onSubmit={handleChangePIN} className="space-y-6">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Current PIN
                </label>
                <input
                  type="password"
                  inputMode="numeric"
                  pattern="\d{4}"
                  maxLength={4}
                  value={oldPIN}
                  onChange={(e) => setOldPIN(e.target.value.replace(/\D/g, ''))}
                  placeholder="••••"
                  className="w-full px-4 py-3 text-2xl tracking-widest text-center border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
                  required
                />
              </div>

              <div className="border-t border-gray-200 pt-6">
                <div className="mb-4">
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    New PIN
                  </label>
                  <input
                    type="password"
                    inputMode="numeric"
                    pattern="\d{4}"
                    maxLength={4}
                    value={newPIN}
                    onChange={(e) => setNewPIN(e.target.value.replace(/\D/g, ''))}
                    placeholder="••••"
                    className="w-full px-4 py-3 text-2xl tracking-widest text-center border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
                    required
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Confirm New PIN
                  </label>
                  <input
                    type="password"
                    inputMode="numeric"
                    pattern="\d{4}"
                    maxLength={4}
                    value={confirmPIN}
                    onChange={(e) => setConfirmPIN(e.target.value.replace(/\D/g, ''))}
                    placeholder="••••"
                    className="w-full px-4 py-3 text-2xl tracking-widest text-center border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
                    required
                  />
                </div>
              </div>

              <div className="flex gap-3 pt-4">
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => {
                    setOldPIN('');
                    setNewPIN('');
                    setConfirmPIN('');
                  }}
                >
                  Clear
                </Button>
                <Button
                  type="submit"
                  disabled={
                    isSubmitting ||
                    oldPIN.length !== 4 ||
                    newPIN.length !== 4 ||
                    confirmPIN.length !== 4
                  }
                >
                  {isSubmitting ? 'Changing PIN...' : 'Change PIN'}
                </Button>
              </div>
            </form>

            <div className="mt-6 pt-6 border-t border-gray-200">
              <div className="flex items-start gap-2 text-sm text-gray-600">
                <Key className="w-4 h-4 text-gray-400 flex-shrink-0 mt-0.5" />
                <p>
                  If you forgot your current PIN, please contact your manager to reset it.
                </p>
              </div>
            </div>
          </div>
        </div>
    </div>
  );
}
