import React, { useState, useEffect } from 'react';
import { Plus, Edit2, Search, Store as StoreIcon } from 'lucide-react';
import { supabase, StoreServiceWithDetails } from '../lib/supabase';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { Select } from '../components/ui/Select';
import { Drawer } from '../components/ui/Drawer';
import { Badge } from '../components/ui/Badge';
import { useToast } from '../components/ui/Toast';
import { useAuth } from '../contexts/AuthContext';
import { Permissions } from '../lib/permissions';

export function ServicesPage() {
  const [services, setServices] = useState<StoreServiceWithDetails[]>([]);
  const [filteredServices, setFilteredServices] = useState<StoreServiceWithDetails[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterActive, setFilterActive] = useState('all');
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);
  const [editingService, setEditingService] = useState<StoreServiceWithDetails | null>(null);
  const { showToast } = useToast();
  const { session, selectedStoreId } = useAuth();

  const [formData, setFormData] = useState({
    code: '',
    name: '',
    price: '',
    duration_min: '30',
    category: 'Extensions des Ongles',
    active: true,
  });

  useEffect(() => {
    if (selectedStoreId) {
      fetchServices();
    }
  }, [selectedStoreId]);

  useEffect(() => {
    let filtered = services;

    if (searchTerm) {
      filtered = filtered.filter(
        (s) =>
          s.code.toLowerCase().includes(searchTerm.toLowerCase()) ||
          s.name.toLowerCase().includes(searchTerm.toLowerCase())
      );
    }

    if (filterActive !== 'all') {
      filtered = filtered.filter((s) => s.active === (filterActive === 'active'));
    }

    setFilteredServices(filtered);
  }, [services, searchTerm, filterActive]);

  async function fetchServices() {
    if (!selectedStoreId) {
      showToast('Please select a store first', 'error');
      return;
    }

    try {
      const { data, error } = await supabase.rpc('get_services_by_popularity', {
        p_store_id: selectedStoreId,
      });

      if (error) throw error;
      const fetchedServices = data || [];
      setServices(fetchedServices);
      setFilteredServices(fetchedServices);
    } catch (error) {
      console.error('Error fetching services:', error);
      showToast('Failed to load services', 'error');
    } finally {
      setLoading(false);
    }
  }

  function openDrawer(service?: StoreServiceWithDetails) {
    if (!session || !session.role || !Permissions.services.canEdit(session.role)) {
      showToast('You do not have permission to edit services', 'error');
      return;
    }
    if (service) {
      setEditingService(service);
      setFormData({
        code: service.code,
        name: service.name,
        price: service.price.toString(),
        duration_min: service.duration_min.toString(),
        category: service.category,
        active: service.active,
      });
    } else {
      setEditingService(null);
      setFormData({
        code: '',
        name: '',
        price: '',
        duration_min: '30',
        category: 'Extensions des Ongles',
        active: true,
      });
    }
    setIsDrawerOpen(true);
  }

  function closeDrawer() {
    setIsDrawerOpen(false);
    setEditingService(null);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    if (!session || !session.role || !Permissions.services.canEdit(session.role)) {
      showToast('You do not have permission to save services', 'error');
      return;
    }

    if (!selectedStoreId) {
      showToast('No store selected', 'error');
      return;
    }

    if (!formData.price || !formData.duration_min) {
      showToast('Please fill in all required fields', 'error');
      return;
    }

    try {
      if (editingService) {
        const { error } = await supabase
          .from('store_services')
          .update({
            price_override: parseFloat(formData.price),
            duration_override: parseInt(formData.duration_min),
            active: formData.active,
            updated_at: new Date().toISOString(),
          })
          .eq('id', editingService.store_service_id);

        if (error) throw error;
        showToast('Service updated successfully', 'success');
      }

      await fetchServices();
      closeDrawer();
    } catch (error: any) {
      console.error('Error saving service:', error);
      showToast('Failed to save service', 'error');
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading services...</div>
      </div>
    );
  }

  if (!selectedStoreId) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <StoreIcon className="w-12 h-12 text-gray-400 mx-auto mb-3" />
          <p className="text-gray-500">Please select a store to manage services</p>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto">
      <div className="mb-3">
        <h2 className="text-lg font-bold text-gray-900">Store Services</h2>
        <p className="text-xs text-gray-600 mt-1">
          Manage pricing and availability for this store's services
        </p>
      </div>

      <div className="bg-white rounded-lg shadow">
        <div className="p-2 border-b border-gray-200 flex gap-2">
          <div className="flex-1">
            <div className="relative">
              <Search className="absolute left-2 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4" />
              <input
                type="text"
                placeholder="Search by code or name..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full pl-8 pr-3 py-1 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
          </div>
          <Select
            value={filterActive}
            onChange={(e) => setFilterActive(e.target.value)}
            options={[
              { value: 'all', label: 'All Services' },
              { value: 'active', label: 'Active Only' },
              { value: 'inactive', label: 'Inactive Only' },
            ]}
          />
        </div>

        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Code
                </th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Name
                </th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Category
                </th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Price
                </th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Duration
                </th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {filteredServices.map((service) => (
                <tr
                  key={service.store_service_id}
                  onClick={() => openDrawer(service)}
                  className="hover:bg-gray-50 cursor-pointer"
                >
                  <td className="px-3 py-2 whitespace-nowrap text-xs font-medium text-gray-900">
                    {service.code}
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap text-xs text-gray-900">
                    {service.name}
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap text-xs text-gray-600">
                    {service.category}
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap text-xs text-gray-900">
                    ${service.price.toFixed(2)}
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap text-xs text-gray-600">
                    {service.duration_min} min
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap">
                    <Badge variant={service.active ? 'success' : 'default'}>
                      {service.active ? 'Active' : 'Inactive'}
                    </Badge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {filteredServices.length === 0 && (
          <div className="text-center py-8">
            <p className="text-sm text-gray-500">No services found</p>
          </div>
        )}
      </div>

      <Drawer
        isOpen={isDrawerOpen}
        onClose={closeDrawer}
        title={editingService ? 'Edit Store Service' : 'Service Details'}
      >
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-3 mb-4">
            <p className="text-xs text-blue-800">
              You are editing the pricing and availability for this service at your store.
              Service details (code, name, category) cannot be changed here.
            </p>
          </div>

          <Input
            label="Service Code"
            value={formData.code}
            disabled
            readOnly
          />
          <Input
            label="Service Name"
            value={formData.name}
            disabled
            readOnly
          />
          <Input
            label="Category"
            value={formData.category}
            disabled
            readOnly
          />
          <Input
            label="Store Price *"
            type="number"
            step="0.01"
            min="0"
            value={formData.price}
            onChange={(e) => setFormData({ ...formData, price: e.target.value })}
            placeholder="0.00"
            required
          />
          <Input
            label="Duration (minutes) *"
            type="number"
            min="1"
            value={formData.duration_min}
            onChange={(e) =>
              setFormData({ ...formData, duration_min: e.target.value })
            }
            required
          />
          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="active"
              checked={formData.active}
              onChange={(e) => setFormData({ ...formData, active: e.target.checked })}
              className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
            />
            <label htmlFor="active" className="text-sm text-gray-700">
              Active (available for this store)
            </label>
          </div>
          <div className="flex gap-3 pt-4">
            <Button type="button" variant="ghost" onClick={closeDrawer}>
              Cancel
            </Button>
            <Button type="submit">
              Update Service
            </Button>
          </div>
        </form>
      </Drawer>
    </div>
  );
}
