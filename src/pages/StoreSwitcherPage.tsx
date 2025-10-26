import { useState, useEffect } from 'react';
import { Store as StoreIcon, Check } from 'lucide-react';
import { supabase, Store } from '../lib/supabase';
import { useAuth } from '../contexts/AuthContext';
import { useToast } from '../components/ui/Toast';

interface StoreSwitcherPageProps {
  onStoreSelected: () => void;
}

export function StoreSwitcherPage({ onStoreSelected }: StoreSwitcherPageProps) {
  const [stores, setStores] = useState<Store[]>([]);
  const [selectedStore, setSelectedStore] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const { session, selectStore, t } = useAuth();
  const { showToast } = useToast();

  useEffect(() => {
    fetchStores();
  }, []);

  async function fetchStores() {
    try {
      if (!session?.employee_id) {
        setLoading(false);
        return;
      }

      const { data: employeeStores } = await supabase
        .from('employee_stores')
        .select('store_id')
        .eq('employee_id', session.employee_id);

      const employeeStoreIds = employeeStores?.map(es => es.store_id) || [];

      const { data, error } = await supabase
        .from('stores')
        .select('*')
        .eq('active', true)
        .order('name');

      if (error) throw error;

      let availableStores = data || [];

      if (employeeStoreIds.length > 0) {
        availableStores = availableStores.filter(store =>
          employeeStoreIds.includes(store.id)
        );
      }

      setStores(availableStores);

      if (availableStores.length > 0) {
        setSelectedStore(availableStores[0].id);
      }
    } catch (error) {
      showToast(t('messages.failed'), 'error');
    } finally {
      setLoading(false);
    }
  }

  function handleContinue() {
    if (!selectedStore) {
      showToast(t('forms.selectOption'), 'error');
      return;
    }

    selectStore(selectedStore);
    onStoreSelected();
  }

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-blue-100">
        <div className="text-gray-500">{t('messages.loading')}</div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-blue-100 flex items-center justify-center p-4">
      <div className="w-full max-w-4xl">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-blue-600 rounded-full mb-4">
            <StoreIcon className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-3xl font-bold text-gray-900 mb-2">Salon360</h1>
          <p className="text-gray-600">{t('store.selectStore')}</p>
          {session?.display_name && (
            <p className="text-sm text-gray-500 mt-2">
              {t('auth.welcome')}, {session.display_name}
            </p>
          )}
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {stores.map((store) => (
            <button
              key={store.id}
              onClick={() => setSelectedStore(store.id)}
              className={`relative bg-white rounded-xl p-6 shadow-lg transition-all duration-200 hover:shadow-xl ${
                selectedStore === store.id
                  ? 'ring-4 ring-blue-500 transform scale-105'
                  : 'hover:scale-102'
              }`}
            >
              {selectedStore === store.id && (
                <div className="absolute top-3 right-3 w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center">
                  <Check className="w-5 h-5 text-white" />
                </div>
              )}

              <div className="flex flex-col items-center text-center">
                <div className={`w-16 h-16 rounded-full flex items-center justify-center mb-4 ${
                  selectedStore === store.id
                    ? 'bg-blue-100'
                    : 'bg-gray-100'
                }`}>
                  <StoreIcon className={`w-8 h-8 ${
                    selectedStore === store.id
                      ? 'text-blue-600'
                      : 'text-gray-600'
                  }`} />
                </div>

                <h3 className="text-xl font-bold text-gray-900 mb-1">
                  {store.name}
                </h3>

                <div className={`inline-block px-3 py-1 rounded-full text-sm font-medium ${
                  selectedStore === store.id
                    ? 'bg-blue-100 text-blue-700'
                    : 'bg-gray-100 text-gray-600'
                }`}>
                  {store.code}
                </div>
              </div>
            </button>
          ))}
        </div>

        <div className="text-center">
          <button
            onClick={handleContinue}
            className="bg-blue-600 hover:bg-blue-700 text-white font-semibold text-lg px-12 py-4 rounded-xl shadow-lg transition-all duration-200 hover:shadow-xl hover:scale-105 transform"
          >
            Continue
          </button>
        </div>

        {stores.length === 0 && (
          <div className="text-center mt-8">
            <p className="text-gray-600">{t('store.noStores')}</p>
            <p className="text-sm text-gray-500 mt-2">
              {t('store.contactAdmin')}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
