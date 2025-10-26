import React, { useState, useEffect } from 'react';
import { X, Plus, Trash2, Banknote, CreditCard, Clock, Award, Lock, CheckCircle, AlertCircle } from 'lucide-react';
import {
  supabase,
  SaleTicket,
  TicketItemWithDetails,
  Service,
  StoreServiceWithDetails,
  Technician,
  TicketActivityLog,
  TechnicianWithQueue,
} from '../lib/supabase';
import { Button } from './ui/Button';
import { Input } from './ui/Input';
import { Select } from './ui/Select';
import { Modal } from './ui/Modal';
import { useToast } from './ui/Toast';
import { useAuth } from '../contexts/AuthContext';
import { Permissions } from '../lib/permissions';

interface TicketEditorProps {
  ticketId: string | null;
  onClose: () => void;
  selectedDate: string;
}

interface TicketItemForm {
  id?: string;
  service_id: string;
  employee_id: string;
  qty: string;
  price_each: string;
  tip_customer: string;
  tip_receptionist: string;
  addon_details: string;
  addon_price: string;
  service?: Service;
  employee?: Technician;
  is_custom?: boolean;
  custom_service_name?: string;
}

export function TicketEditor({ ticketId, onClose, selectedDate }: TicketEditorProps) {
  const [ticket, setTicket] = useState<SaleTicket | null>(null);
  const [items, setItems] = useState<TicketItemForm[]>([]);
  const [services, setServices] = useState<StoreServiceWithDetails[]>([]);
  const [employees, setEmployees] = useState<Technician[]>([]);
  const [sortedTechnicians, setSortedTechnicians] = useState<TechnicianWithQueue[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [lastUsedEmployeeId, setLastUsedEmployeeId] = useState<string>('');
  const [activityLogs, setActivityLogs] = useState<TicketActivityLog[]>([]);
  const [showActivityModal, setShowActivityModal] = useState(false);
  const { showToast } = useToast();
  const { session, selectedStoreId } = useAuth();

  const isApproved = ticket?.approval_status === 'approved' || ticket?.approval_status === 'auto_approved';

  const isReadOnly = ticket && session && session.role_permission && !Permissions.tickets.canEdit(
    session.role_permission,
    !!ticket.closed_at,
    isApproved
  );

  const canEditNotes = session && session.role_permission && ticket && Permissions.tickets.canEditNotes(
    session.role_permission,
    !!ticket.closed_at
  );

  const canClose = session && session.role_permission && Permissions.tickets.canClose(session.role_permission);

  const canReopen = session && session.role_permission && Permissions.tickets.canReopen(session.role_permission);

  const canDelete = session && session.role_permission && Permissions.tickets.canDelete(session.role_permission);

  const [selectedTechnicianId, setSelectedTechnicianId] = useState<string>('');
  const [showCustomService, setShowCustomService] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [currentTime, setCurrentTime] = useState(new Date());

  const calculateTimeRemaining = (tech: TechnicianWithQueue): string => {
    if (!tech.ticket_start_time || !tech.estimated_duration_min) {
      return '';
    }

    const startTime = new Date(tech.ticket_start_time);
    const elapsedMinutes = Math.floor((currentTime.getTime() - startTime.getTime()) / (1000 * 60));
    const remainingMinutes = Math.max(0, tech.estimated_duration_min - elapsedMinutes);

    if (remainingMinutes === 0) {
      return 'Finishing soon';
    }

    if (remainingMinutes < 60) {
      return `~${remainingMinutes}min`;
    }

    const hours = Math.floor(remainingMinutes / 60);
    const mins = remainingMinutes % 60;
    return mins > 0 ? `~${hours}h ${mins}min` : `~${hours}h`;
  };

  const canEmployeePerformService = (employeeId: string, serviceId: string): boolean => {
    const employee = employees.find(e => e.id === employeeId);
    const service = services.find(s => s.id === serviceId);

    if (!employee || !service) return true;

    const isSpaExpert = employee.role.includes('Spa Expert');
    if (isSpaExpert) {
      const allowedCategories = ['Soins de Pédicure', 'Soins de Manucure', 'Others'];
      return allowedCategories.includes(service.category);
    }

    // Technicians and other roles can perform all services
    return true;
  };

  const getServiceColor = (category: string): string => {
    const colorMap: Record<string, string> = {
      'Soins de Pédicure': 'bg-blue-100 text-blue-800 hover:bg-blue-200 border-2 border-blue-300',
      'Soins de Manucure': 'bg-pink-100 text-pink-800 hover:bg-pink-200 border-2 border-pink-300',
      'Extensions des Ongles': 'bg-purple-100 text-purple-800 hover:bg-purple-200 border-2 border-purple-300',
      'Others': 'bg-teal-100 text-teal-800 hover:bg-teal-200 border-2 border-teal-300',
    };
    return colorMap[category] || 'bg-gray-100 text-gray-700 hover:bg-gray-200 border-2 border-gray-300';
  };

  const [formData, setFormData] = useState({
    customer_type: '' as '' | 'Appointment' | 'Requested' | 'Assigned',
    customer_name: '',
    customer_phone: '',
    payment_method: '' as '' | SaleTicket['payment_method'],
    tip_customer: '',
    tip_receptionist: '',
    addon_details: '',
    addon_price: '',
    discount_percentage: '',
    discount_amount: '',
    notes: '',
  });

  useEffect(() => {
    loadData();
  }, [ticketId]);

  useEffect(() => {
    if (selectedStoreId) {
      fetchSortedTechnicians();

      const queueChannel = supabase
        .channel(`ready-queue-${selectedStoreId}`)
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'technician_ready_queue',
            filter: `store_id=eq.${selectedStoreId}`,
          },
          () => {
            fetchSortedTechnicians();
          }
        )
        .on(
          'postgres_changes',
          {
            event: 'UPDATE',
            schema: 'public',
            table: 'sale_tickets',
            filter: `store_id=eq.${selectedStoreId}`,
          },
          () => {
            fetchSortedTechnicians();
          }
        )
        .subscribe();

      return () => {
        supabase.removeChannel(queueChannel);
      };
    }
  }, [selectedStoreId]);

  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentTime(new Date());
    }, 60000);

    return () => {
      clearInterval(timer);
    };
  }, []);

  async function fetchSortedTechnicians() {
    if (!selectedStoreId) return;

    try {
      const { data, error } = await supabase.rpc('get_sorted_technicians_for_store', {
        p_store_id: selectedStoreId
      });

      if (error) throw error;

      setSortedTechnicians(data || []);

      if (data && data.length > 0) {
        setLastUsedEmployeeId(data[0].employee_id);
      }
    } catch (error) {
      console.error('Error fetching sorted technicians:', error);
    }
  }

  async function loadData() {
    try {
      setLoading(true);

      const [servicesRes, employeesRes] = await Promise.all([
        supabase.rpc('get_services_by_popularity', {
          p_store_id: selectedStoreId
        }),
        supabase
          .from('employees')
          .select('*')
          .or('status.eq.Active,status.eq.active')
          .order('display_name'),
      ]);

      if (servicesRes.error) throw servicesRes.error;
      if (employeesRes.error) throw employeesRes.error;

      setServices(servicesRes.data || []);

      const allEmployees = (employeesRes.data || []).filter(emp =>
        emp.role.includes('Technician') || emp.role.includes('Spa Expert')
      );
      const filteredEmployees = selectedStoreId
        ? allEmployees.filter(emp => !emp.store_id || emp.store_id === selectedStoreId)
        : allEmployees;

      setEmployees(filteredEmployees);

      if (filteredEmployees.length > 0) {
        setLastUsedEmployeeId(filteredEmployees[0].id);
      }

      await fetchSortedTechnicians();

      if (ticketId) {
        const { data: ticketData, error: ticketError } = await supabase
          .from('sale_tickets')
          .select(
            `
            *,
            ticket_items (
              *,
              service:services(*),
              employee:employees!ticket_items_employee_id_fkey(*)
            )
          `
          )
          .eq('id', ticketId)
          .single();

        if (ticketError) throw ticketError;

        setTicket(ticketData);

        const ticketItems = (ticketData as any).ticket_items || [];
        const firstItem = ticketItems[0];

        setFormData({
          customer_type: ticketData.customer_type || '',
          customer_name: ticketData.customer_name,
          customer_phone: ticketData.customer_phone || '',
          payment_method: ticketData.payment_method || '',
          tip_customer: firstItem ? (parseFloat(firstItem.tip_customer_cash || 0) + parseFloat(firstItem.tip_customer_card || 0)).toString() : '0',
          tip_receptionist: firstItem ? parseFloat(firstItem.tip_receptionist || 0).toString() : '0',
          addon_details: firstItem?.addon_details || '',
          addon_price: firstItem ? parseFloat(firstItem.addon_price || 0).toString() : '0',
          discount_percentage: firstItem ? parseFloat(firstItem.discount_percentage || 0).toString() : '0',
          discount_amount: firstItem ? parseFloat(firstItem.discount_amount || 0).toString() : '0',
          notes: ticketData.notes,
        });

        setItems(
          ticketItems.map((item: any) => ({
            id: item.id,
            service_id: item.service_id || '',
            employee_id: item.employee_id,
            qty: parseFloat(item.qty || 0).toString(),
            price_each: parseFloat(item.price_each || 0).toString(),
            tip_customer: (parseFloat(item.tip_customer_cash || 0) + parseFloat(item.tip_customer_card || 0)).toString(),
            tip_receptionist: parseFloat(item.tip_receptionist || 0).toString(),
            addon_details: item.addon_details || '',
            addon_price: parseFloat(item.addon_price || 0).toString(),
            service: item.service,
            employee: item.employee,
            is_custom: !item.service_id,
            custom_service_name: item.custom_service_name || '',
          }))
        );

        if (ticketItems.length > 0 && ticketItems[0].custom_service_name) {
          setShowCustomService(true);
        }

        if (firstItem?.employee_id) {
          setSelectedTechnicianId(firstItem.employee_id);
        }

        await fetchActivityLogs(ticketId);
      }
    } catch (error) {
      showToast('Failed to load data', 'error');
    } finally {
      setLoading(false);
    }
  }

  async function fetchActivityLogs(ticketId: string) {
    try {
      const { data, error } = await supabase
        .from('ticket_activity_log')
        .select(`
          *,
          employee:employees(id, display_name)
        `)
        .eq('ticket_id', ticketId)
        .order('created_at', { ascending: false });

      if (error) throw error;
      setActivityLogs(data || []);
    } catch (error) {
      console.error('Failed to fetch activity logs:', error);
    }
  }

  async function logActivity(ticketId: string, action: TicketActivityLog['action'], description: string, changes?: Record<string, any>) {
    try {
      await supabase
        .from('ticket_activity_log')
        .insert([{
          ticket_id: ticketId,
          employee_id: session?.employee_id,
          action,
          description,
          changes: changes || {},
        }]);
    } catch (error) {
      console.error('Failed to log activity:', error);
    }
  }

  function addItem() {
    const defaultService = services[0];
    setItems([
      ...items,
      {
        service_id: defaultService?.id || '',
        employee_id: lastUsedEmployeeId,
        qty: '1',
        price_each: defaultService?.price.toString() || '0',
        tip_customer: '0',
        tip_receptionist: '0',
        addon_details: '',
        addon_price: '0',
        service: defaultService,
      },
    ]);
  }

  function removeItem(index: number) {
    setItems(items.filter((_, i) => i !== index));
  }

  function updateItem(index: number, field: keyof TicketItemForm, value: string) {
    const newItems = [...items];
    newItems[index] = { ...newItems[index], [field]: value };

    if (field === 'service_id') {
      const service = services.find((s) => s.service_id === value);
      newItems[index].price_each = service?.price.toString() || '0';
      newItems[index].service = service as any;
    }

    if (field === 'employee_id') {
      const employee = employees.find((e) => e.id === value);
      newItems[index].employee = employee;
      setLastUsedEmployeeId(value);
    }

    setItems(newItems);
  }

  function calculateSubtotal(): number {
    const itemsTotal = items.reduce((sum, item) => {
      const qty = parseFloat(item.qty) || 0;
      const price = parseFloat(item.price_each) || 0;
      return sum + (qty * price);
    }, 0);
    const addonPrice = parseFloat(formData.addon_price) || 0;
    return itemsTotal + addonPrice;
  }

  function calculateTotal(): number {
    const subtotal = calculateSubtotal();
    const totalDiscount = calculateTotalDiscount();
    return Math.max(0, subtotal - totalDiscount);
  }

  function calculateTotalTips(): number {
    return (
      (parseFloat(formData.tip_customer) || 0) +
      (parseFloat(formData.tip_receptionist) || 0)
    );
  }

  function calculateCashTips(): number {
    const tipReceptionist = parseFloat(formData.tip_receptionist) || 0;
    if (formData.payment_method === 'Card') {
      return tipReceptionist;
    }
    return (parseFloat(formData.tip_customer) || 0) + tipReceptionist;
  }

  function calculateCardTips(): number {
    if (formData.payment_method === 'Card') {
      return parseFloat(formData.tip_customer) || 0;
    }
    return 0;
  }

  function calculateTotalDiscount(): number {
    const subtotal = calculateSubtotal();
    const discountPercentage = parseFloat(formData.discount_percentage) || 0;
    const discountAmount = parseFloat(formData.discount_amount) || 0;

    const percentageDiscount = (subtotal * discountPercentage) / 100;
    return percentageDiscount + discountAmount;
  }

  function calculateTotalCollected(): number {
    const subtotal = calculateSubtotal();
    const totalTips = calculateTotalTips();
    const totalDiscount = calculateTotalDiscount();

    return Math.max(0, subtotal + totalTips - totalDiscount);
  }

  function handleNumericFieldFocus(event: React.FocusEvent<HTMLInputElement>) {
    const value = event.target.value;
    const numericValue = parseFloat(value);

    // Auto-select text if the field contains 0, 0.00, or is empty
    if (!value || value === '' || numericValue === 0 || value === '0' || value === '0.00' || value === '0.0') {
      event.target.select();
    }
  }

  function handleNumericFieldBlur(event: React.FocusEvent<HTMLInputElement>, fieldName: string) {
    const value = event.target.value;

    // If field is empty or invalid, reset to '0'
    if (!value || value.trim() === '' || isNaN(parseFloat(value))) {
      setFormData({ ...formData, [fieldName]: '0' });
    }
  }

  async function generateTicketNumber(): Promise<string> {
    const dateStr = selectedDate.replace(/-/g, '');

    const { data, error } = await supabase
      .from('sale_tickets')
      .select('ticket_no')
      .like('ticket_no', `ST-${dateStr}-%`)
      .order('ticket_no', { ascending: false })
      .limit(1);

    if (error) throw error;

    let nextNum = 1;
    if (data && data.length > 0) {
      const lastTicket = data[0].ticket_no;
      const lastNum = parseInt(lastTicket.split('-')[2]);
      nextNum = lastNum + 1;
    }

    return `ST-${dateStr}-${nextNum.toString().padStart(4, '0')}`;
  }

  async function handleSaveComment() {
    if (!ticketId || !ticket) return;

    try {
      setSaving(true);

      const { error: updateError } = await supabase
        .from('sale_tickets')
        .update({
          notes: formData.notes,
          saved_by: session?.employee_id,
          updated_at: new Date().toISOString(),
        })
        .eq('id', ticketId);

      if (updateError) throw updateError;

      await logActivity(ticketId, 'updated', `${session?.display_name} added a comment`);

      showToast('Comment saved successfully', 'success');
      onClose();
    } catch (error) {
      console.error('Error saving comment:', error);
      showToast('Failed to save comment', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function handleSave() {
    if (isReadOnly) {
      showToast('You do not have permission to edit this ticket', 'error');
      return;
    }

    if (!ticketId && session && session.role_permission && !Permissions.tickets.canCreate(session.role_permission)) {
      showToast('You do not have permission to create tickets', 'error');
      return;
    }

    if (ticket?.closed_at) {
      showToast('Cannot edit closed ticket', 'error');
      return;
    }

    if (!formData.customer_type) {
      showToast('Customer Type is required', 'error');
      return;
    }

    if (!selectedTechnicianId) {
      showToast('Technician is required', 'error');
      return;
    }

    if (items.length === 0) {
      showToast('Service is required', 'error');
      return;
    }

    for (const item of items) {
      if (item.is_custom) {
        if (!item.custom_service_name || item.custom_service_name.trim() === '') {
          showToast('Custom service name is required', 'error');
          return;
        }
        if (parseFloat(item.price_each) <= 0) {
          showToast('Custom service price must be greater than 0', 'error');
          return;
        }
      } else {
        if (!item.service_id) {
          showToast('Service is required', 'error');
          return;
        }
        if (!canEmployeePerformService(item.employee_id, item.service_id)) {
          const employee = employees.find(e => e.id === item.employee_id);
          const service = services.find(s => s.id === item.service_id);
          showToast(`${employee?.display_name || 'This employee'} cannot perform ${service?.name || 'this service'}. Spa Experts cannot perform Extensions des Ongles services.`, 'error');
          return;
        }
      }
    }

    try {
      setSaving(true);

      const total = calculateTotal();
      const tipCustomer = parseFloat(formData.tip_customer) || 0;
      const tipReceptionist = parseFloat(formData.tip_receptionist) || 0;

      if (ticketId && ticket) {
        const { error: updateError } = await supabase
          .from('sale_tickets')
          .update({
            customer_type: formData.customer_type || null,
            customer_name: formData.customer_name,
            customer_phone: formData.customer_phone,
            payment_method: formData.payment_method,
            total,
            notes: formData.notes,
            saved_by: session?.employee_id,
            updated_at: new Date().toISOString(),
          })
          .eq('id', ticketId);

        if (updateError) throw updateError;

        await logActivity(ticketId, 'updated', `${session?.display_name} updated ticket`, {
          customer_name: formData.customer_name,
          total,
        });

        const existingItemIds = items.filter((item) => item.id).map((item) => item.id);
        const { error: deleteError } = await supabase
          .from('ticket_items')
          .delete()
          .eq('sale_ticket_id', ticketId)
          .not('id', 'in', `(${existingItemIds.join(',')})`);

        for (const item of items) {
          const addonPrice = parseFloat(formData.addon_price) || 0;
          const discountPercentage = parseFloat(formData.discount_percentage) || 0;
          const discountAmount = parseFloat(formData.discount_amount) || 0;

          const isCardPayment = formData.payment_method === 'Card';
          const itemData = {
            sale_ticket_id: ticketId,
            service_id: item.is_custom ? null : item.service_id,
            custom_service_name: item.is_custom ? item.custom_service_name : null,
            employee_id: item.employee_id,
            qty: parseFloat(item.qty),
            price_each: parseFloat(item.price_each),
            tip_customer_cash: isCardPayment ? 0 : tipCustomer,
            tip_customer_card: isCardPayment ? tipCustomer : 0,
            tip_receptionist: tipReceptionist,
            addon_details: formData.addon_details || '',
            addon_price: addonPrice,
            discount_percentage: discountPercentage,
            discount_amount: discountAmount,
            updated_at: new Date().toISOString(),
          };

          if (item.id) {
            const { error } = await supabase
              .from('ticket_items')
              .update(itemData)
              .eq('id', item.id);
            if (error) throw error;
          } else {
            const { error } = await supabase.from('ticket_items').insert([itemData]);
            if (error) throw error;
          }
        }

        showToast('Ticket updated successfully', 'success');
      } else {
        const ticketNo = await generateTicketNumber();
        const tipCustomer = parseFloat(formData.tip_customer) || 0;
        const tipReceptionist = parseFloat(formData.tip_receptionist) || 0;

        const { data: newTicket, error: ticketError } = await supabase
          .from('sale_tickets')
          .insert([
            {
              ticket_no: ticketNo,
              ticket_date: selectedDate,
              customer_type: formData.customer_type || null,
              customer_name: formData.customer_name,
              customer_phone: formData.customer_phone,
              payment_method: formData.payment_method,
              total,
              notes: formData.notes,
              store_id: selectedStoreId || null,
              created_by: session?.employee_id,
              saved_by: session?.employee_id,
            },
          ])
          .select()
          .single();

        if (ticketError) throw ticketError;

        const addonPrice = parseFloat(formData.addon_price) || 0;
        const discountPercentage = parseFloat(formData.discount_percentage) || 0;
        const discountAmount = parseFloat(formData.discount_amount) || 0;
        const isCardPayment = formData.payment_method === 'Card';
        const itemsData = items.map((item) => {
          return {
            sale_ticket_id: newTicket.id,
            service_id: item.is_custom ? null : item.service_id,
            custom_service_name: item.is_custom ? item.custom_service_name : null,
            employee_id: item.employee_id,
            qty: parseFloat(item.qty),
            price_each: parseFloat(item.price_each),
            tip_customer_cash: isCardPayment ? 0 : tipCustomer,
            tip_customer_card: isCardPayment ? tipCustomer : 0,
            tip_receptionist: tipReceptionist,
            addon_details: formData.addon_details || '',
            addon_price: addonPrice,
            discount_percentage: discountPercentage,
            discount_amount: discountAmount,
          };
        });

        const { error: itemsError } = await supabase
          .from('ticket_items')
          .insert(itemsData);

        if (itemsError) throw itemsError;

        await logActivity(newTicket.id, 'created', `${session?.display_name} created ticket`, {
          ticket_no: ticketNo,
          customer_name: formData.customer_name,
          total,
        });

        showToast('Ticket created successfully', 'success');
      }

      onClose();
    } catch (error: any) {
      showToast(error.message || 'Failed to save ticket', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function handleSelectBusyTechnician(technicianId: string, currentTicketId?: string) {
    if (!currentTicketId) {
      setSelectedTechnicianId(technicianId);
      setLastUsedEmployeeId(technicianId);
      if (items.length > 0) {
        updateItem(0, 'employee_id', technicianId);
      }
      return;
    }

    if (!session?.employee_id) {
      console.error('No employee_id in session');
      showToast('Unable to complete ticket: session error', 'error');
      return;
    }

    try {
      console.log('Completing ticket:', currentTicketId, 'for employee:', session.employee_id);

      // Mark the technician's current ticket as completed (stops the timer)
      const { error, data } = await supabase
        .from('sale_tickets')
        .update({
          completed_at: new Date().toISOString(),
          completed_by: session.employee_id,
        })
        .eq('id', currentTicketId)
        .select()
        .maybeSingle();

      if (error) {
        console.error('Error completing ticket:', error);
        showToast(`Failed to complete ticket: ${error.message}`, 'error');
        return;
      }

      if (!data) {
        console.error('No ticket found with ID:', currentTicketId);
        showToast('Ticket not found', 'error');
        return;
      }

      console.log('Ticket completed successfully:', data);

      await logActivity(currentTicketId, 'updated', `${session.display_name} marked service as completed (technician assigned to new ticket)`, {});

      setSelectedTechnicianId(technicianId);
      setLastUsedEmployeeId(technicianId);
      if (items.length > 0) {
        updateItem(0, 'employee_id', technicianId);
      }

      showToast('Previous ticket marked as completed', 'success');

      // Refresh technician list to update statuses
      await fetchTechnicians();
    } catch (error: any) {
      console.error('Failed to complete previous ticket:', error);
      showToast(error?.message || 'Failed to complete previous ticket', 'error');
    }
  }

  async function handleCloseTicket() {
    if (!canClose) {
      showToast('You do not have permission to close tickets', 'error');
      return;
    }

    if (!ticketId || !ticket) return;

    if (items.length === 0) {
      showToast('Cannot close ticket with no items', 'error');
      return;
    }

    if (!formData.payment_method || (formData.payment_method !== 'Cash' && formData.payment_method !== 'Card')) {
      showToast('Please select a payment method (Cash or Card) before closing the ticket', 'error');
      return;
    }

    const total = calculateTotal();
    if (total < 0) {
      showToast('Cannot close ticket with negative total', 'error');
      return;
    }

    try {
      await handleSave();

      const closerRoles = session?.role || [];

      const { error } = await supabase
        .from('sale_tickets')
        .update({
          closed_at: new Date().toISOString(),
          closed_by: session?.employee_id,
          closed_by_roles: closerRoles,
        })
        .eq('id', ticketId);

      if (error) throw error;

      await logActivity(ticketId, 'closed', `${session?.display_name} closed ticket`, {
        total: calculateTotal(),
        closed_by_roles: closerRoles,
      });

      showToast('Ticket closed successfully. Approval workflow initiated.', 'success');
      onClose();
    } catch (error) {
      showToast('Failed to close ticket', 'error');
    }
  }

  async function handleReopenTicket() {
    if (!canReopen) {
      showToast('You do not have permission to reopen tickets', 'error');
      return;
    }

    if (!ticketId || !ticket) {
      showToast('Invalid ticket', 'error');
      return;
    }

    try {
      setSaving(true);

      const { error, data } = await supabase
        .from('sale_tickets')
        .update({
          closed_at: null,
          closed_by: null,
          closed_by_roles: null,
          requires_higher_approval: false,
          approval_status: null,
          approval_deadline: null,
          approved_at: null,
          approved_by: null,
          rejection_reason: null,
          requires_admin_review: false,
          completed_at: null,
          completed_by: null,
        })
        .eq('id', ticketId)
        .select();

      if (error) {
        console.error('Database error reopening ticket:', error);
        throw error;
      }

      await logActivity(ticketId, 'updated', `${session?.display_name} reopened ticket`, {
        reopened: true,
      });

      showToast('Ticket reopened successfully', 'success');
      onClose();
    } catch (error: any) {
      console.error('Error reopening ticket:', error);
      showToast(error?.message || 'Failed to reopen ticket', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function handleMarkCompleted() {
    if (!ticketId || !ticket) return;

    if (ticket.closed_at) {
      showToast('Cannot mark closed ticket as completed', 'error');
      return;
    }

    if (ticket.completed_at) {
      showToast('Ticket is already marked as completed', 'error');
      return;
    }

    try {
      setSaving(true);

      const { error } = await supabase
        .from('sale_tickets')
        .update({
          completed_at: new Date().toISOString(),
          completed_by: session?.employee_id,
        })
        .eq('id', ticketId);

      if (error) throw error;

      await logActivity(ticketId, 'updated', `${session?.display_name} marked ticket as completed`, {
        completed_at: new Date().toISOString(),
      });

      showToast('Ticket marked as completed (timer stopped)', 'success');
      onClose();
    } catch (error) {
      console.error('Error marking ticket as completed:', error);
      showToast('Failed to mark ticket as completed', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function handleDeleteTicket() {
    if (!canDelete) {
      showToast('You do not have permission to delete tickets', 'error');
      return;
    }

    if (!ticketId || !ticket) {
      showToast('No ticket to delete', 'error');
      return;
    }

    if (ticket.closed_at) {
      showToast('Cannot delete closed tickets', 'error');
      return;
    }

    try {
      setSaving(true);

      await logActivity(ticketId, 'deleted', `${session?.display_name} deleted ticket`, {
        ticket_no: ticket.ticket_no,
        customer_name: formData.customer_name,
        total: calculateTotal(),
        items_count: items.length,
      });

      const { error } = await supabase
        .from('sale_tickets')
        .delete()
        .eq('id', ticketId);

      if (error) throw error;

      showToast('Ticket deleted successfully', 'success');
      onClose();
    } catch (error) {
      console.error('Error deleting ticket:', error);
      showToast('Failed to delete ticket', 'error');
    } finally {
      setSaving(false);
      setShowDeleteConfirm(false);
    }
  }

  if (loading) {
    return (
      <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center">
        <div className="bg-white p-6 rounded-lg">
          <p className="text-gray-500">Loading...</p>
        </div>
      </div>
    );
  }

  const isTicketClosed = ticket?.closed_at !== null && ticket?.closed_at !== undefined;

  function getApprovalStatusBadge() {
    if (!ticket?.approval_status) return null;

    switch (ticket.approval_status) {
      case 'pending_approval':
        return (
          <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-orange-100 text-orange-800">
            <Clock className="w-3 h-3 mr-1" />
            Pending Approval
          </span>
        );
      case 'approved':
        return (
          <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
            <CheckCircle className="w-3 h-3 mr-1" />
            Approved
          </span>
        );
      case 'auto_approved':
        return (
          <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
            <Clock className="w-3 h-3 mr-1" />
            Auto-Approved
          </span>
        );
      case 'rejected':
        return (
          <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-red-100 text-red-800">
            <AlertCircle className="w-3 h-3 mr-1" />
            Rejected
          </span>
        );
      default:
        return null;
    }
  }

  function getTimeUntilDeadline(): string | null {
    if (!ticket?.approval_deadline || ticket.approval_status !== 'pending_approval') return null;

    const deadline = new Date(ticket.approval_deadline);
    const now = new Date();
    const diffMs = deadline.getTime() - now.getTime();
    const diffHours = diffMs / (1000 * 60 * 60);

    if (diffHours < 0) return 'Expired';
    if (diffHours < 1) {
      const minutes = Math.floor(diffHours * 60);
      return `${minutes} min remaining`;
    }
    const hours = Math.floor(diffHours);
    const minutes = Math.floor((diffHours - hours) * 60);
    return minutes > 0 ? `${hours}h ${minutes}m remaining` : `${hours}h remaining`;
  }

  if (!ticketId && session && !Permissions.tickets.canCreate(session.role_permission)) {
    return (
      <>
        <div
          className="fixed inset-0 bg-black bg-opacity-50 z-40"
          onClick={onClose}
        />
        <div className="fixed inset-0 md:right-0 md:left-auto md:top-0 h-full w-full md:max-w-4xl bg-white shadow-xl z-50 overflow-y-auto flex items-center justify-center">
          <div className="bg-white rounded-lg p-8 max-w-md mx-4 text-center">
            <AlertCircle className="w-16 h-16 text-red-500 mx-auto mb-4" />
            <h3 className="text-lg font-semibold text-gray-900 mb-2">Access Denied</h3>
            <p className="text-gray-600 mb-6">
              You do not have permission to create tickets. Only Admin and Receptionist roles can create new tickets.
            </p>
            <Button onClick={onClose} variant="primary">
              Close
            </Button>
          </div>
        </div>
      </>
    );
  }

  return (
    <>
      <div
        className="fixed inset-0 bg-black bg-opacity-50 z-40"
        onClick={onClose}
      />
      <div className="fixed inset-0 md:right-0 md:left-auto md:top-0 h-full w-full md:max-w-2xl bg-white shadow-xl z-50 overflow-y-auto">
        <div className="sticky top-0 bg-white border-b border-gray-200 px-3 md:px-4 py-3 md:py-2">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <div>
                <h2 className="text-base font-semibold text-gray-900">
                  {ticketId ? `Ticket ${ticket?.ticket_no}` : 'New Ticket'}
                </h2>
                <div className="flex items-center gap-2 mt-1">
                  {isTicketClosed && !ticket?.approval_status && (
                    <p className="text-xs text-green-600 font-medium">Closed</p>
                  )}
                </div>
              </div>
            </div>
            <div className="flex items-center gap-2">
              {getApprovalStatusBadge()}
              <button
                onClick={onClose}
                className="text-gray-400 hover:text-gray-600 transition-colors p-2 -mr-2 min-h-[44px] min-w-[44px] flex items-center justify-center"
              >
                <X className="w-6 h-6 md:w-5 md:h-5" />
              </button>
            </div>
          </div>
        </div>

        <div className="p-3 md:p-4 space-y-4 md:space-y-3 pb-20 md:pb-4">
          {ticket?.approval_status === 'pending_approval' && ticket.approval_deadline && (
            <div className="bg-orange-50 border border-orange-200 rounded-lg p-3">
              <div className="flex items-start gap-2">
                <Clock className="w-4 h-4 text-orange-600 mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-orange-900">Awaiting Technician Approval</p>
                  <p className="text-xs text-orange-700 mt-1">
                    {getTimeUntilDeadline()} until automatic approval
                  </p>
                </div>
              </div>
            </div>
          )}

          {ticket?.approval_status === 'rejected' && ticket.requires_admin_review && (
            <div className="bg-red-50 border border-red-200 rounded-lg p-3">
              <div className="flex items-start gap-2">
                <AlertCircle className="w-4 h-4 text-red-600 mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-red-900">Ticket Rejected</p>
                  <p className="text-xs text-red-700 mt-1">
                    Reason: {ticket.rejection_reason || 'No reason provided'}
                  </p>
                  <p className="text-xs text-red-600 mt-1 font-medium">
                    This ticket requires admin review before any changes can be made.
                  </p>
                </div>
              </div>
            </div>
          )}

          {ticket?.closed_by === session?.employee_id && ticket?.approval_status === 'pending_approval' && (
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
              <div className="flex items-start gap-2">
                <AlertCircle className="w-4 h-4 text-blue-600 mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-blue-900">You closed this ticket</p>
                  <p className="text-xs text-blue-700 mt-1">
                    You cannot approve tickets you closed. The assigned technician must approve it.
                  </p>
                </div>
              </div>
            </div>
          )}

          {isApproved && (
            <div className="bg-green-50 border border-green-200 rounded-lg p-3">
              <div className="flex items-start gap-2">
                <CheckCircle className="w-4 h-4 text-green-600 mt-0.5" />
                <div className="flex-1">
                  <p className="text-sm font-medium text-green-900">
                    {ticket?.approval_status === 'approved' ? 'Ticket Approved' : 'Ticket Auto-Approved'}
                  </p>
                  {ticket?.approved_at && (
                    <p className="text-xs text-green-700 mt-1">
                      {ticket.approval_status === 'approved' ? 'Approved' : 'Auto-approved'} on {new Date(ticket.approved_at).toLocaleString()}
                    </p>
                  )}
                </div>
              </div>
            </div>
          )}
          <div className="border border-gray-200 rounded-lg p-3 bg-purple-50">
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Customer Type <span className="text-red-600">*</span>
            </label>
            <div className="flex gap-2 mb-2">
              <button
                type="button"
                onClick={() => setFormData({ ...formData, customer_type: 'Appointment' })}
                className={`flex-1 py-3 md:py-1.5 px-3 text-sm rounded-lg font-medium transition-colors min-h-[48px] md:min-h-0 ${
                  formData.customer_type === 'Appointment'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-600'
                }`}
                disabled={isTicketClosed || isReadOnly}
              >
                Appointment
              </button>
              <button
                type="button"
                onClick={() => setFormData({ ...formData, customer_type: 'Requested' })}
                className={`flex-1 py-3 md:py-1.5 px-3 text-sm rounded-lg font-medium transition-colors min-h-[48px] md:min-h-0 ${
                  formData.customer_type === 'Requested'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-600'
                }`}
                disabled={isTicketClosed || isReadOnly}
              >
                Requested
              </button>
              <button
                type="button"
                onClick={() => setFormData({ ...formData, customer_type: 'Assigned' })}
                className={`flex-1 py-3 md:py-1.5 px-3 text-sm rounded-lg font-medium transition-colors min-h-[48px] md:min-h-0 ${
                  formData.customer_type === 'Assigned'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-600'
                }`}
                disabled={isTicketClosed || isReadOnly}
              >
                Assigned
              </button>
            </div>
            <div className="flex gap-2">
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-700 mb-0.5">
                  Name
                </label>
                <input
                  value={formData.customer_name}
                  onChange={(e) =>
                    setFormData({ ...formData, customer_name: e.target.value })
                  }
                  placeholder="e.g. John"
                  disabled={isTicketClosed}
                  className="w-full px-3 py-3 md:py-1.5 text-base md:text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[48px] md:min-h-0"
                />
              </div>
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-700 mb-0.5">
                  Phone Number (Optional)
                </label>
                <input
                  value={formData.customer_phone}
                  onChange={(e) =>
                    setFormData({ ...formData, customer_phone: e.target.value })
                  }
                  placeholder="e.g. 1234"
                  disabled={isTicketClosed}
                  className="w-full px-3 py-3 md:py-1.5 text-base md:text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[48px] md:min-h-0"
                />
              </div>
            </div>
          </div>

          <div className="border border-gray-200 rounded-lg p-3 bg-blue-50">
            <label className="block text-xs font-medium text-gray-700 mb-2">
              Technician <span className="text-red-600">*</span>
            </label>

            {!isTicketClosed && (
              <div className="flex items-start gap-3 mb-2">
                {sortedTechnicians.filter(t => t.queue_status === 'ready').length > 0 && (
                  <div className="flex items-center gap-2">
                    <Award className="w-3.5 h-3.5 text-green-600" />
                    <span className="text-xs font-semibold text-green-700 uppercase whitespace-nowrap">Available</span>
                  </div>
                )}
                {sortedTechnicians.filter(t => t.queue_status === 'neutral').length > 0 && (
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold text-gray-600 uppercase whitespace-nowrap">Not Ready</span>
                  </div>
                )}
                {sortedTechnicians.filter(t => t.queue_status === 'busy').length > 0 && (
                  <div className="flex items-center gap-2">
                    <Lock className="w-3.5 h-3.5 text-red-600" />
                    <span className="text-xs font-semibold text-red-700 uppercase whitespace-nowrap">Busy</span>
                  </div>
                )}
              </div>
            )}

            <div className="flex flex-wrap gap-2">
              {!isTicketClosed && sortedTechnicians.filter(t => t.queue_status === 'ready').map((tech) => (
                <button
                  key={tech.employee_id}
                  type="button"
                  onClick={() => {
                    setSelectedTechnicianId(tech.employee_id);
                    setLastUsedEmployeeId(tech.employee_id);
                    if (items.length > 0) {
                      updateItem(0, 'employee_id', tech.employee_id);
                    }
                  }}
                  className={`relative py-3 md:py-1.5 px-4 md:px-3 text-sm rounded-lg font-medium transition-colors min-h-[48px] md:min-h-0 ${
                    selectedTechnicianId === tech.employee_id
                      ? 'bg-green-600 text-white ring-2 ring-green-400'
                      : 'bg-green-100 text-green-800 hover:bg-green-200'
                  }`}
                  disabled={isTicketClosed || isReadOnly}
                >
                  <div className="flex items-center gap-2">
                    {tech.queue_position > 0 && (
                      <span className="inline-flex items-center justify-center w-5 h-5 text-xs font-bold bg-white text-green-600 rounded-full">
                        {tech.queue_position}
                      </span>
                    )}
                    <span>{tech.display_name}</span>
                  </div>
                </button>
              ))}

              {!isTicketClosed && sortedTechnicians.filter(t => t.queue_status === 'neutral').map((tech) => (
                <button
                  key={tech.employee_id}
                  type="button"
                  onClick={() => {
                    setSelectedTechnicianId(tech.employee_id);
                    setLastUsedEmployeeId(tech.employee_id);
                    if (items.length > 0) {
                      updateItem(0, 'employee_id', tech.employee_id);
                    }
                  }}
                  className={`py-3 md:py-1.5 px-4 md:px-3 text-sm rounded-lg font-medium transition-colors min-h-[48px] md:min-h-0 ${
                    selectedTechnicianId === tech.employee_id
                      ? 'bg-blue-600 text-white'
                      : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-600'
                  }`}
                  disabled={isTicketClosed || isReadOnly}
                >
                  {tech.display_name}
                </button>
              ))}

              {!isTicketClosed && sortedTechnicians.filter(t => t.queue_status === 'busy').map((tech) => {
                const timeRemaining = calculateTimeRemaining(tech);
                return (
                  <button
                    key={tech.employee_id}
                    type="button"
                    onClick={() => handleSelectBusyTechnician(tech.employee_id, tech.current_open_ticket_id)}
                    className={`py-3 md:py-1.5 px-4 md:px-3 text-sm rounded-lg font-medium transition-colors min-h-[48px] md:min-h-0 ${
                      selectedTechnicianId === tech.employee_id
                        ? 'bg-red-600 text-white ring-2 ring-red-400'
                        : 'bg-red-100 text-red-800 hover:bg-red-200'
                    }`}
                    title={`${tech.display_name} is currently working on ${tech.open_ticket_count} ticket(s)${timeRemaining ? ` - ${timeRemaining} remaining` : ''}. Click to complete their current ticket and assign to new ticket.`}
                    disabled={isReadOnly}
                  >
                    <div className="flex items-center gap-2">
                      <Lock className="w-3 h-3" />
                      <span>{tech.display_name}</span>
                      {timeRemaining && (
                        <span className="inline-flex items-center text-xs font-medium">
                          {timeRemaining}
                        </span>
                      )}
                    </div>
                  </button>
                );
              })}

              {isTicketClosed && items.length > 0 && Array.from(new Set(items.map(item => item.employee_id))).map((employeeId) => {
                const item = items.find(i => i.employee_id === employeeId);
                if (!item?.employee) return null;
                return (
                  <div
                    key={employeeId}
                    className="py-3 md:py-1.5 px-4 md:px-3 text-sm rounded-lg font-medium bg-gray-100 text-gray-700 min-h-[48px] md:min-h-0 flex items-center"
                  >
                    {item.employee.display_name}
                  </div>
                );
              })}
            </div>

            {!isTicketClosed && sortedTechnicians.length === 0 && (
              <div className="text-center py-3 text-sm text-gray-500">
                No technicians available
              </div>
            )}
          </div>

          <div>
            <h3 className="text-sm font-semibold text-gray-900 mb-2">
              Service Item <span className="text-red-600">*</span>
            </h3>
            {items.length === 0 ? (
              <div className="border border-gray-200 rounded-lg p-3">
                {!isTicketClosed && services.length > 0 && (
                  <div className="flex flex-wrap gap-2">
                    {services
                      .filter(service => canEmployeePerformService(selectedTechnicianId || lastUsedEmployeeId, service.service_id))
                      .map((service) => (
                      <button
                        key={service.store_service_id}
                        type="button"
                        onClick={() => {
                          setItems([{
                            service_id: service.service_id,
                            employee_id: selectedTechnicianId || lastUsedEmployeeId,
                            qty: '1',
                            price_each: service.price.toString(),
                            tip_customer: '0',
                            tip_receptionist: '0',
                            addon_details: '',
                            addon_price: '0',
                            service: service as any,
                            is_custom: false,
                          }]);
                        }}
                        className={`py-3 md:py-1.5 px-4 md:px-3 text-sm rounded-lg font-medium transition-colors min-h-[48px] md:min-h-0 ${getServiceColor(service.category)}`}
                      >
                        {service.code}
                      </button>
                    ))}
                    <button
                      type="button"
                      onClick={() => {
                        setShowCustomService(true);
                        setItems([{
                          service_id: '',
                          employee_id: selectedTechnicianId || lastUsedEmployeeId,
                          qty: '1',
                          price_each: '0',
                          tip_customer: '0',
                          tip_receptionist: '0',
                          addon_details: '',
                          addon_price: '0',
                          is_custom: true,
                          custom_service_name: '',
                        }]);
                      }}
                      className="py-3 md:py-1.5 px-4 md:px-3 text-sm rounded-lg font-medium transition-colors min-h-[48px] md:min-h-0 bg-gray-100 text-gray-800 hover:bg-gray-200 border-2 border-gray-300"
                    >
                      CUSTOM
                    </button>
                  </div>
                )}
              </div>
            ) : (
              <div className="border border-gray-200 rounded-lg p-3 space-y-3">
                <div className="flex items-start gap-2">
                  <div className="flex-1">
                    {items[0].is_custom ? (
                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-0.5">
                          Service Name
                        </label>
                        <input
                          type="text"
                          value={items[0].custom_service_name || ''}
                          onChange={(e) => {
                            const updatedItems = [...items];
                            updatedItems[0].custom_service_name = e.target.value;
                            setItems(updatedItems);
                          }}
                          className="w-full px-3 py-3 md:py-1.5 text-base md:text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[48px] md:min-h-0"
                          placeholder="Enter custom service name"
                          disabled={isTicketClosed || isReadOnly}
                        />
                      </div>
                    ) : (
                      <Select
                        label="Service"
                        value={items[0].service_id}
                        onChange={(e) => updateItem(0, 'service_id', e.target.value)}
                        options={services
                          .filter(s => canEmployeePerformService(items[0]?.employee_id || selectedTechnicianId || lastUsedEmployeeId, s.id))
                          .map((s) => ({
                            value: s.id,
                            label: `${s.code} - ${s.name}`,
                          }))}
                        disabled={isTicketClosed || isReadOnly}
                      />
                    )}
                  </div>
                  <div className="w-24">
                    <label className="block text-xs font-medium text-gray-700 mb-0.5">
                      Price
                    </label>
                    <div className="relative">
                      <span className="absolute left-2 top-1/2 -translate-y-1/2 text-sm text-gray-500">$</span>
                      <input
                        type="number"
                        step="0.01"
                        min="0"
                        value={items[0].price_each}
                        onChange={(e) =>
                          updateItem(0, 'price_each', e.target.value)
                        }
                        className="w-full pl-6 pr-2 py-3 md:py-1.5 text-base md:text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[48px] md:min-h-0"
                        disabled={isTicketClosed || isReadOnly}
                      />
                    </div>
                  </div>
                  {!isTicketClosed && (
                    <div className="flex items-end">
                      <button
                        onClick={() => {
                          setItems([]);
                          setShowCustomService(false);
                        }}
                        className="p-1.5 text-red-600 hover:text-red-800 hover:bg-red-50 rounded"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  )}
                </div>

                <div className="flex items-end gap-2">
                  <div className="flex-1">
                    <label className="block text-xs font-medium text-gray-700 mb-1">
                      Add-ons
                    </label>
                    <Input
                      value={formData.addon_details}
                      onChange={(e) =>
                        setFormData({ ...formData, addon_details: e.target.value })
                      }
                      placeholder="Enter add-on details"
                      disabled={isTicketClosed || isReadOnly}
                    />
                  </div>
                  <div className="w-24">
                    <label className="block text-xs font-medium text-gray-700 mb-0.5">
                      Price
                    </label>
                    <div className="relative">
                      <span className="absolute left-2 top-1/2 -translate-y-1/2 text-sm text-gray-500">$</span>
                      <input
                        type="number"
                        step="0.01"
                        min="0"
                        value={formData.addon_price}
                        onChange={(e) =>
                          setFormData({ ...formData, addon_price: e.target.value })
                        }
                        onFocus={handleNumericFieldFocus}
                        onBlur={(e) => handleNumericFieldBlur(e, 'addon_price')}
                        className="w-full pl-6 pr-2 py-3 md:py-1.5 text-base md:text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[48px] md:min-h-0"
                        disabled={isTicketClosed || isReadOnly}
                      />
                    </div>
                  </div>
                </div>
              </div>
            )}
          </div>

          <div>
            <h3 className="text-sm font-semibold text-gray-900 mb-2">
              Payment Method <span className="text-red-600">*</span>
            </h3>
            <div className="border border-gray-200 rounded-lg p-3 bg-green-50">
              <div className="flex gap-2 mb-2">
                <button
                  type="button"
                  onClick={() => setFormData({ ...formData, payment_method: 'Cash' })}
                  className={`flex-1 py-3 md:py-1.5 px-3 text-sm rounded-lg font-medium transition-colors flex items-center justify-center gap-1.5 min-h-[48px] md:min-h-0 ${
                    formData.payment_method === 'Cash'
                      ? 'bg-blue-600 text-white'
                      : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-600'
                  }`}
                  disabled={isTicketClosed || isReadOnly}
                >
                  <Banknote className="w-4 h-4" />
                  Cash
                </button>
                <button
                  type="button"
                  onClick={() => setFormData({ ...formData, payment_method: 'Card' })}
                  className={`flex-1 py-3 md:py-1.5 px-3 text-sm rounded-lg font-medium transition-colors flex items-center justify-center gap-1.5 min-h-[48px] md:min-h-0 ${
                    formData.payment_method === 'Card'
                      ? 'bg-blue-600 text-white'
                      : 'bg-gray-100 text-gray-700 hover:bg-gray-200 border border-gray-600'
                  }`}
                  disabled={isTicketClosed || isReadOnly}
                >
                  <CreditCard className="w-4 h-4" />
                  Card
                </button>
              </div>
              <div className="grid grid-cols-2 gap-2 mb-2">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-0.5">
                    Tip Given by Customer
                  </label>
                  <div className="relative">
                    <span className="absolute left-2 top-1/2 -translate-y-1/2 text-sm text-gray-500">$</span>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      value={formData.tip_customer}
                      onChange={(e) =>
                        setFormData({ ...formData, tip_customer: e.target.value })
                      }
                      onFocus={handleNumericFieldFocus}
                      onBlur={(e) => handleNumericFieldBlur(e, 'tip_customer')}
                      className="w-full pl-6 pr-2 py-3 md:py-1.5 text-base md:text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[48px] md:min-h-0"
                      disabled={isTicketClosed || isReadOnly}
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-0.5">
                    Tip Paired by Receptionist
                  </label>
                  <div className="relative">
                    <span className="absolute left-2 top-1/2 -translate-y-1/2 text-sm text-gray-500">$</span>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      value={formData.tip_receptionist}
                      onChange={(e) =>
                        setFormData({ ...formData, tip_receptionist: e.target.value })
                      }
                      onFocus={handleNumericFieldFocus}
                      onBlur={(e) => handleNumericFieldBlur(e, 'tip_receptionist')}
                      className="w-full pl-6 pr-2 py-3 md:py-1.5 text-base md:text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[48px] md:min-h-0"
                      disabled={isTicketClosed || isReadOnly}
                    />
                  </div>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-0.5">
                    Discount Amount
                  </label>
                  <div className="relative">
                    <span className="absolute left-2 top-1/2 -translate-y-1/2 text-sm text-gray-500">$</span>
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      value={formData.discount_amount}
                      onChange={(e) =>
                        setFormData({ ...formData, discount_amount: e.target.value })
                      }
                      onFocus={handleNumericFieldFocus}
                      onBlur={(e) => handleNumericFieldBlur(e, 'discount_amount')}
                      className="w-full pl-6 pr-2 py-3 md:py-1.5 text-base md:text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[48px] md:min-h-0"
                      disabled={isTicketClosed || isReadOnly}
                      placeholder="0.00"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-0.5">
                    Discount Percentage
                  </label>
                  <div className="relative">
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      max="100"
                      value={formData.discount_percentage}
                      onChange={(e) =>
                        setFormData({ ...formData, discount_percentage: e.target.value })
                      }
                      onFocus={handleNumericFieldFocus}
                      onBlur={(e) => handleNumericFieldBlur(e, 'discount_percentage')}
                      className="w-full pl-2 pr-8 py-3 md:py-1.5 text-base md:text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[48px] md:min-h-0"
                      disabled={isTicketClosed || isReadOnly}
                      placeholder="0"
                    />
                    <span className="absolute right-2 top-1/2 -translate-y-1/2 text-sm text-gray-500">%</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div className="border-t border-gray-200 pt-2 space-y-1">
            <div className="flex justify-between items-center text-base font-bold text-gray-900">
              <span>Total Service Price:</span>
              <span>${calculateSubtotal().toFixed(2)}</span>
            </div>
            <div className="flex justify-between items-center text-sm font-semibold text-green-600">
              <span>Total Tips (Cash):</span>
              <span>${calculateCashTips().toFixed(2)}</span>
            </div>
            <div className="flex justify-between items-center text-sm font-semibold text-blue-600">
              <span>Total Tips (Card):</span>
              <span>${calculateCardTips().toFixed(2)}</span>
            </div>
            <div className="flex justify-between items-center text-base font-bold text-purple-600 pt-1 border-t border-gray-200">
              <span>Total Collected:</span>
              <span>${calculateTotalCollected().toFixed(2)}</span>
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Notes / Comments
            </label>
            <textarea
              value={formData.notes}
              onChange={(e) =>
                setFormData({ ...formData, notes: e.target.value })
              }
              rows={1}
              className="w-full px-2 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              disabled={!canEditNotes}
              placeholder={canEditNotes ? "Add notes or comments..." : ""}
            />
          </div>

          <div className="flex justify-between items-center gap-1.5 pt-2 fixed md:static bottom-0 left-0 right-0 bg-white p-2 md:p-0 shadow-lg md:shadow-none z-10">
            <div className="flex gap-1.5">
              <button
                onClick={onClose}
                className="px-2 py-1 text-xs bg-white border border-gray-300 text-gray-700 rounded hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed transition-colors font-medium min-h-[36px] md:min-h-0"
              >
                Close
              </button>
              {!isTicketClosed && !isReadOnly && canDelete && ticketId && (
                <button
                  onClick={() => setShowDeleteConfirm(true)}
                  disabled={saving}
                  className="px-2 py-1 text-xs bg-red-600 text-white rounded hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center gap-1 font-medium min-h-[36px] md:min-h-0"
                >
                  <Trash2 className="w-3 h-3" />
                  Delete
                </button>
              )}
              {!isTicketClosed && !isReadOnly && (
                <>
                  <button
                    onClick={handleSave}
                    disabled={saving}
                    className="px-2 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors font-medium min-h-[36px] md:min-h-0"
                  >
                    {saving ? 'Saving...' : 'Save'}
                  </button>
                  {ticketId && !ticket?.completed_at && (
                    <button
                      onClick={handleMarkCompleted}
                      disabled={saving}
                      className="px-2 py-1 text-xs bg-gray-600 text-white rounded hover:bg-gray-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center gap-1 font-medium min-h-[36px] md:min-h-0"
                    >
                      <CheckCircle className="w-3 h-3" />
                      Complete
                    </button>
                  )}
                  {ticketId && (
                    <button
                      onClick={handleCloseTicket}
                      disabled={saving}
                      className="px-2 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors font-medium min-h-[36px] md:min-h-0"
                    >
                      Close Ticket
                    </button>
                  )}
                </>
              )}
              {isTicketClosed && canReopen && ticketId && (
                <button
                  onClick={handleReopenTicket}
                  disabled={saving}
                  className="px-2 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors font-medium min-h-[36px] md:min-h-0"
                >
                  {saving ? 'Reopening...' : 'Reopen Ticket'}
                </button>
              )}
              {isReadOnly && canEditNotes && ticketId && !canReopen && (
                <button
                  onClick={handleSaveComment}
                  disabled={saving}
                  className="px-2 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors font-medium min-h-[36px] md:min-h-0"
                >
                  {saving ? 'Saving...' : 'Save Comment'}
                </button>
              )}
            </div>
            {ticketId && activityLogs.length > 0 && (
              <button
                onClick={() => setShowActivityModal(true)}
                className="px-2 py-1 text-xs bg-gray-100 text-gray-700 rounded hover:bg-gray-200 transition-colors flex items-center gap-1 font-medium min-h-[36px] md:min-h-0"
              >
                <Clock className="w-3 h-3" />
                Activity
              </button>
            )}
          </div>
        </div>
      </div>

      <Modal
        isOpen={showActivityModal}
        onClose={() => setShowActivityModal(false)}
        title="Ticket Activity Log"
      >
        <div className="space-y-3">
          {activityLogs.length === 0 ? (
            <p className="text-sm text-gray-500 text-center py-4">No activity logs yet</p>
          ) : (
            activityLogs.map((log) => (
              <div key={log.id} className="border-l-4 border-blue-500 bg-gray-50 px-4 py-3 rounded-r-lg">
                <div className="flex items-start justify-between mb-1">
                  <div className="flex items-center gap-2">
                    <span className={`text-xs font-semibold uppercase px-2 py-0.5 rounded ${
                      log.action === 'created' ? 'bg-green-100 text-green-800' :
                      log.action === 'updated' ? 'bg-blue-100 text-blue-800' :
                      log.action === 'closed' ? 'bg-gray-100 text-gray-800' :
                      'bg-purple-100 text-purple-800'
                    }`}>
                      {log.action}
                    </span>
                    <span className="text-sm font-medium text-gray-900">
                      {log.employee?.display_name || 'Unknown'}
                    </span>
                  </div>
                  <span className="text-xs text-gray-500">
                    {new Date(log.created_at).toLocaleString()}
                  </span>
                </div>
                <p className="text-sm text-gray-700">{log.description}</p>
                {log.changes && Object.keys(log.changes).length > 0 && (
                  <div className="mt-2 text-xs text-gray-600 bg-white px-2 py-1 rounded">
                    {Object.entries(log.changes).map(([key, value]) => (
                      <div key={key}>
                        <strong>{key}:</strong> {JSON.stringify(value)}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))
          )}
        </div>
      </Modal>

      <Modal
        isOpen={showDeleteConfirm}
        onClose={() => setShowDeleteConfirm(false)}
        title="Delete Ticket"
      >
        <div className="space-y-4">
          <div className="flex items-start gap-3 p-4 bg-red-50 border border-red-200 rounded-lg">
            <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="text-sm font-medium text-red-900 mb-1">
                Warning: This action cannot be undone
              </p>
              <p className="text-sm text-red-700">
                You are about to permanently delete this open ticket. All ticket information and associated items will be removed.
              </p>
            </div>
          </div>

          {ticket && (
            <div className="bg-gray-50 rounded-lg p-4 space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Ticket Number:</span>
                <span className="font-medium text-gray-900">{ticket.ticket_no}</span>
              </div>
              {formData.customer_name && (
                <div className="flex justify-between text-sm">
                  <span className="text-gray-600">Customer:</span>
                  <span className="font-medium text-gray-900">{formData.customer_name}</span>
                </div>
              )}
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Total Amount:</span>
                <span className="font-medium text-gray-900">${calculateTotal().toFixed(2)}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Services:</span>
                <span className="font-medium text-gray-900">{items.length} item{items.length !== 1 ? 's' : ''}</span>
              </div>
            </div>
          )}

          <div className="flex gap-3 pt-2">
            <Button
              variant="ghost"
              onClick={() => setShowDeleteConfirm(false)}
              disabled={saving}
              className="flex-1"
            >
              Cancel
            </Button>
            <button
              onClick={handleDeleteTicket}
              disabled={saving}
              className="flex-1 px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors font-medium text-sm"
            >
              {saving ? 'Deleting...' : 'Delete Ticket'}
            </button>
          </div>
        </div>
      </Modal>
    </>
  );
}
