import React, { useState, useEffect } from 'react';
import { Plus, Edit2, Search, RefreshCw } from 'lucide-react';
import { supabase, Employee, Store } from '../lib/supabase';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { Select } from '../components/ui/Select';
import { MultiSelect } from '../components/ui/MultiSelect';
import { Drawer } from '../components/ui/Drawer';
import { Badge } from '../components/ui/Badge';
import { Modal } from '../components/ui/Modal';
import { useToast } from '../components/ui/Toast';
import { useAuth } from '../contexts/AuthContext';
import { resetPIN } from '../lib/auth';
import { Permissions } from '../lib/permissions';

export function EmployeesPage() {
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [filteredEmployees, setFilteredEmployees] = useState<Employee[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [employeeStoresMap, setEmployeeStoresMap] = useState<Record<string, string[]>>({});
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterStatus, setFilterStatus] = useState('all');
  const [filterRole, setFilterRole] = useState('all');
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);
  const [editingEmployee, setEditingEmployee] = useState<Employee | null>(null);
  const [resetModalOpen, setResetModalOpen] = useState(false);
  const [resetEmployee, setResetEmployee] = useState<Employee | null>(null);
  const [tempPIN, setTempPIN] = useState('');
  const { showToast } = useToast();
  const { session, selectedStoreId, t } = useAuth();

  const [formData, setFormData] = useState({
    display_name: '',
    role: ['Technician'] as Employee['role'],
    status: 'Active' as Employee['status'],
    pay_type: 'hourly' as 'hourly' | 'daily',
    store_ids: [] as string[],
    notes: '',
  });

  useEffect(() => {
    fetchStores();
  }, []);

  useEffect(() => {
    fetchEmployees();
  }, [selectedStoreId]);

  useEffect(() => {
    let filtered = employees;

    if (searchTerm) {
      filtered = filtered.filter(
        (e) =>
          e.display_name.toLowerCase().includes(searchTerm.toLowerCase())
      );
    }

    if (filterStatus !== 'all') {
      filtered = filtered.filter((e) => e.status === filterStatus);
    }

    if (filterRole !== 'all') {
      filtered = filtered.filter((e) => e.role.includes(filterRole as any));
    }

    setFilteredEmployees(filtered);
  }, [employees, searchTerm, filterStatus, filterRole]);

  async function fetchStores() {
    try {
      const { data, error } = await supabase
        .from('stores')
        .select('*')
        .order('name');

      if (error) throw error;
      setStores(data || []);
    } catch (error) {
      showToast(t('messages.failed'), 'error');
    }
  }

  async function fetchEmployees() {
    try {
      const { data, error } = await supabase
        .from('employees')
        .select('*')
        .order('display_name');

      if (error) throw error;

      const allEmployees = (data || []).filter(emp =>
        emp.role.includes('Technician') || emp.role.includes('Receptionist') || emp.role.includes('Supervisor') || emp.role.includes('Spa Expert')
      );

      const { data: employeeStoresData } = await supabase
        .from('employee_stores')
        .select('employee_id, store_id');

      const storesMap: Record<string, string[]> = {};
      employeeStoresData?.forEach(es => {
        if (!storesMap[es.employee_id]) {
          storesMap[es.employee_id] = [];
        }
        storesMap[es.employee_id].push(es.store_id);
      });

      setEmployeeStoresMap(storesMap);

      const filteredByStore = selectedStoreId
        ? allEmployees.filter(emp =>
            !storesMap[emp.id] ||
            storesMap[emp.id].length === 0 ||
            storesMap[emp.id].includes(selectedStoreId)
          )
        : allEmployees;

      setEmployees(filteredByStore);
      setFilteredEmployees(filteredByStore);
    } catch (error) {
      showToast(t('messages.failed'), 'error');
    } finally {
      setLoading(false);
    }
  }

  function openDrawer(employee?: Employee) {
    if (employee) {
      setEditingEmployee(employee);
      const storeIds = employeeStoresMap[employee.id] || [];
      setFormData({
        display_name: employee.display_name,
        role: employee.role,
        status: employee.status,
        pay_type: employee.pay_type || 'hourly',
        store_ids: storeIds,
        notes: employee.notes,
      });
    } else {
      setEditingEmployee(null);
      setFormData({
        display_name: '',
        role: ['Technician'],
        status: 'Active',
        pay_type: 'hourly',
        store_ids: [],
        notes: '',
      });
    }
    setIsDrawerOpen(true);
  }

  function closeDrawer() {
    setIsDrawerOpen(false);
    setEditingEmployee(null);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    if (!formData.display_name) {
      showToast(t('forms.required'), 'error');
      return;
    }

    try {
      let rolePermission: 'Technician' | 'Receptionist' | 'Supervisor';

      if (formData.role.includes('Supervisor')) {
        rolePermission = 'Supervisor';
      } else if (formData.role.includes('Receptionist') || formData.role.includes('Manager') || formData.role.includes('Owner')) {
        rolePermission = 'Receptionist';
      } else {
        rolePermission = 'Technician';
      }

      const employeeData = {
        display_name: formData.display_name,
        legal_name: formData.display_name,
        role: formData.role,
        role_permission: rolePermission,
        status: formData.status,
        pay_type: formData.pay_type,
        notes: formData.notes,
        updated_at: new Date().toISOString(),
      };

      let employeeId: string;

      if (editingEmployee) {
        const { error } = await supabase
          .from('employees')
          .update(employeeData)
          .eq('id', editingEmployee.id);

        if (error) throw error;
        employeeId = editingEmployee.id;

        await supabase
          .from('employee_stores')
          .delete()
          .eq('employee_id', employeeId);
      } else {
        const { data: newEmployee, error } = await supabase
          .from('employees')
          .insert([employeeData])
          .select('id')
          .single();

        if (error) throw error;
        if (!newEmployee) throw new Error('Failed to create employee');
        employeeId = newEmployee.id;
      }

      if (formData.store_ids.length > 0) {
        const employeeStoreRecords = formData.store_ids.map(storeId => ({
          employee_id: employeeId,
          store_id: storeId,
        }));

        const { error: storesError } = await supabase
          .from('employee_stores')
          .insert(employeeStoreRecords);

        if (storesError) throw storesError;
      }

      showToast(
        editingEmployee ? t('messages.saved') : t('messages.saved'),
        'success'
      );

      await fetchEmployees();
      closeDrawer();
    } catch (error) {
      showToast(t('messages.failed'), 'error');
    }
  }

  async function handleResetPIN(employee: Employee) {
    if (!session || !Permissions.employees.canResetPIN(session.role)) {
      showToast('You do not have permission to reset PINs', 'error');
      return;
    }

    try {
      const result = await resetPIN(employee.id);
      if (result.success) {
        setTempPIN(result.tempPIN);
        setResetEmployee(employee);
        setResetModalOpen(true);
        showToast(t('emp.pinReset'), 'success');
      } else {
        showToast(result.error || 'Failed to reset PIN', 'error');
      }
    } catch (error) {
      showToast('Failed to reset PIN', 'error');
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">{t('messages.loading')}</div>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-lg font-bold text-gray-900">{t('emp.title')}</h2>
        <Button size="sm" onClick={() => openDrawer()}>
          <Plus className="w-3 h-3 mr-1" />
          {t('actions.add')}
        </Button>
      </div>

      <div className="bg-white rounded-lg shadow">
        <div className="p-2 border-b border-gray-200 flex gap-2">
          <div className="flex-1">
            <div className="relative">
              <Search className="absolute left-2 top-1/2 transform -translate-y-1/2 text-gray-400 w-4 h-4" />
              <input
                type="text"
                placeholder={t('actions.search')}
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full pl-8 pr-3 py-1 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
          </div>
          <Select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
            options={[
              { value: 'all', label: 'All Status' },
              { value: 'Active', label: t('emp.active') },
              { value: 'Inactive', label: t('emp.inactive') },
            ]}
          />
          <Select
            value={filterRole}
            onChange={(e) => setFilterRole(e.target.value)}
            options={[
              { value: 'all', label: 'All Roles' },
              { value: 'Technician', label: t('emp.technician') },
              { value: 'Spa Expert', label: t('emp.spaExpert') },
              { value: 'Receptionist', label: t('emp.receptionist') },
              { value: 'Supervisor', label: t('emp.supervisor') },
              { value: 'Manager', label: t('emp.manager') },
              { value: 'Owner', label: t('emp.owner') },
            ]}
          />
        </div>

        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('emp.displayName')}
                </th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('emp.role')}
                </th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('emp.status')}
                </th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('emp.assignedStores')}
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {filteredEmployees.map((employee) => {
                const assignedStores = employeeStoresMap[employee.id] || [];
                const storeNames = assignedStores
                  .map(storeId => stores.find(s => s.id === storeId)?.code)
                  .filter(Boolean)
                  .join(', ');

                return (
                  <tr
                    key={employee.id}
                    onClick={() => openDrawer(employee)}
                    className="hover:bg-gray-50 cursor-pointer"
                  >
                    <td className="px-3 py-2 whitespace-nowrap text-xs font-medium text-gray-900">
                      {employee.display_name}
                    </td>
                    <td className="px-3 py-2 text-xs text-gray-900">
                      <div className="flex flex-wrap gap-1">
                        {employee.role.map((r) => (
                          <Badge key={r} variant="default">
                            {r}
                          </Badge>
                        ))}
                      </div>
                    </td>
                    <td className="px-3 py-2 whitespace-nowrap">
                      <Badge variant={employee.status === 'Active' ? 'success' : 'default'}>
                        {employee.status}
                      </Badge>
                    </td>
                    <td className="px-3 py-2 text-xs text-gray-600">
                      {assignedStores.length === 0 ? (
                        <span className="text-gray-400 italic">All stores</span>
                      ) : (
                        <span>{storeNames}</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        {filteredEmployees.length === 0 && (
          <div className="text-center py-8">
            <p className="text-sm text-gray-500">No employees found</p>
          </div>
        )}
      </div>

      <Drawer
        isOpen={isDrawerOpen}
        onClose={closeDrawer}
        title={editingEmployee ? t('actions.edit') : t('actions.add')}
      >
        <form onSubmit={handleSubmit} className="space-y-4">
          <Input
            label={`${t('emp.displayName')} *`}
            value={formData.display_name}
            onChange={(e) =>
              setFormData({ ...formData, display_name: e.target.value })
            }
            required
          />
          <MultiSelect
            label={`${t('emp.role')} *`}
            value={formData.role}
            onChange={(values) =>
              setFormData({
                ...formData,
                role: values as Employee['role'],
              })
            }
            options={[
              { value: 'Technician', label: t('emp.technician') },
              { value: 'Spa Expert', label: t('emp.spaExpert') },
              { value: 'Receptionist', label: t('emp.receptionist') },
              { value: 'Supervisor', label: t('emp.supervisor') },
              { value: 'Manager', label: t('emp.manager') },
              { value: 'Owner', label: t('emp.owner') },
            ]}
            placeholder="Select roles"
          />
          <Select
            label={`${t('emp.status')} *`}
            value={formData.status}
            onChange={(e) =>
              setFormData({
                ...formData,
                status: e.target.value as Employee['status'],
              })
            }
            options={[
              { value: 'Active', label: t('emp.active') },
              { value: 'Inactive', label: t('emp.inactive') },
            ]}
          />
          {session && session.role && (session.role.includes('Owner') || session.role.includes('Manager')) && (
            <Select
              label="Pay Type *"
              value={formData.pay_type}
              onChange={(e) =>
                setFormData({
                  ...formData,
                  pay_type: e.target.value as 'hourly' | 'daily',
                })
              }
              options={[
                { value: 'hourly', label: 'Hourly' },
                { value: 'daily', label: 'Daily' },
              ]}
            />
          )}
          <MultiSelect
            label={t('emp.assignedStores')}
            value={formData.store_ids}
            onChange={(values) =>
              setFormData({
                ...formData,
                store_ids: values,
              })
            }
            options={stores.map(store => ({
              value: store.id,
              label: `${store.name} (${store.code})`
            }))}
            placeholder="Select stores (No stores = No access)"
          />
          {editingEmployee && session && Permissions.employees.canResetPIN(session.role) && (
            <div>
              <button
                type="button"
                onClick={() => handleResetPIN(editingEmployee)}
                className="w-full px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors flex items-center justify-center gap-2 text-sm font-medium"
              >
                Change PIN
              </button>
            </div>
          )}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              {t('tickets.notes')}
            </label>
            <textarea
              value={formData.notes}
              onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
              rows={3}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <div className="flex gap-3 pt-4">
            <Button type="button" variant="ghost" onClick={closeDrawer}>
              {t('actions.cancel')}
            </Button>
            <Button type="submit">
              {editingEmployee ? t('actions.save') : t('actions.add')}
            </Button>
          </div>
        </form>
      </Drawer>

      <Modal
        isOpen={resetModalOpen}
        onClose={() => {
          setResetModalOpen(false);
          setTempPIN('');
          setResetEmployee(null);
        }}
        title={t('emp.resetPIN')}
      >
        <div className="space-y-4">
          <p className="text-sm text-gray-600">
            PIN has been reset for <strong>{resetEmployee?.display_name}</strong>
          </p>
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <p className="text-xs text-blue-800 mb-2 font-medium">{t('emp.tempPIN')}:</p>
            <p className="text-3xl font-bold text-blue-900 text-center tracking-wider">
              {tempPIN}
            </p>
          </div>
          <p className="text-xs text-gray-500">
            Please provide this temporary PIN to the employee. They will be able to use it to log in.
          </p>
          <div className="flex justify-end">
            <Button
              onClick={() => {
                setResetModalOpen(false);
                setTempPIN('');
                setResetEmployee(null);
              }}
            >
              {t('actions.close')}
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
