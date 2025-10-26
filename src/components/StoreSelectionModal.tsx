import { useState, useEffect } from 'react';
import { Modal } from './ui/Modal';
import { supabase } from '../lib/supabase';
import { Store } from 'lucide-react';

interface StoreSelectionModalProps {
  isOpen: boolean;
  storeIds: string[];
  onSelect: (storeId: string) => void;
}

export function StoreSelectionModal({ isOpen, storeIds, onSelect }: StoreSelectionModalProps) {
  const [stores, setStores] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    if (isOpen && storeIds.length > 0) {
      loadStores();
    }
  }, [isOpen, storeIds]);

  async function loadStores() {
    setIsLoading(true);
    try {
      const { data, error } = await supabase
        .from('stores')
        .select('id, name')
        .in('id', storeIds)
        .eq('active', true)
        .order('name');

      if (error) throw error;

      setStores(data || []);
    } catch (error) {
      console.error('Error loading stores:', error);
    } finally {
      setIsLoading(false);
    }
  }

  function handleStoreSelect(storeId: string) {
    onSelect(storeId);
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={() => {}}
      title="Select Store"
    >
      <div className="space-y-4">
        <p className="text-sm text-gray-600">
          You have access to multiple stores. Please select which store you want to work with.
        </p>

        {isLoading ? (
          <div className="text-center py-4">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto"></div>
          </div>
        ) : (
          <div className="space-y-2">
            {stores.map((store) => (
              <button
                key={store.id}
                onClick={() => handleStoreSelect(store.id)}
                className="w-full flex items-center p-4 border border-gray-300 rounded-lg cursor-pointer transition-colors hover:border-blue-400 hover:bg-blue-50"
              >
                <Store className="w-5 h-5 mr-3 text-gray-600" />
                <span className="font-medium">{store.name}</span>
              </button>
            ))}
          </div>
        )}
      </div>
    </Modal>
  );
}
