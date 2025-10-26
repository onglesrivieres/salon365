import { useState, useEffect, useRef } from 'react';
import { Users, Briefcase, DollarSign, LogOut, Settings, Store as StoreIcon, ChevronDown, Calendar, Menu, X, CheckCircle, Home, Receipt, Star } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { canAccessPage, Permissions } from '../lib/permissions';
import { supabase, Store } from '../lib/supabase';
import { NotificationBadge } from './ui/NotificationBadge';
import { VersionNotification } from './VersionNotification';
import { initializeVersionCheck, startVersionCheck } from '../lib/version';

interface LayoutProps {
  children: React.ReactNode;
  currentPage: 'home' | 'tickets' | 'eod' | 'technicians' | 'services' | 'settings' | 'attendance' | 'approvals';
  onNavigate: (page: 'home' | 'tickets' | 'eod' | 'technicians' | 'services' | 'settings' | 'attendance' | 'approvals') => void;
}

export function Layout({ children, currentPage, onNavigate }: LayoutProps) {
  const { session, selectedStoreId, selectStore, logout, t } = useAuth();
  const [currentStore, setCurrentStore] = useState<Store | null>(null);
  const [allStores, setAllStores] = useState<Store[]>([]);
  const [isStoreDropdownOpen, setIsStoreDropdownOpen] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [pendingApprovalsCount, setPendingApprovalsCount] = useState(0);
  const [hasNewVersion, setHasNewVersion] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (selectedStoreId) {
      fetchStore();
    }
    if (session?.employee_id) {
      fetchAllStores();
    }
    if (session?.employee_id && session?.role && Permissions.tickets.canViewPendingApprovals(session.role)) {
      fetchPendingApprovalsCount();
    }
  }, [selectedStoreId, session]);

  useEffect(() => {
    if (!session?.employee_id || !session?.role || !Permissions.tickets.canViewPendingApprovals(session.role) || !selectedStoreId) return;

    // Poll every 30 seconds for pending approvals
    const interval = setInterval(() => {
      fetchPendingApprovalsCount();
    }, 30000);

    // Subscribe to real-time changes on sale_tickets table
    const approvalsChannel = supabase
      .channel(`approvals-${selectedStoreId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'sale_tickets',
          filter: `store_id=eq.${selectedStoreId}`,
        },
        (payload) => {
          // Refresh count when tickets are closed, approved, or updated
          if (payload.eventType === 'UPDATE' || payload.eventType === 'INSERT') {
            fetchPendingApprovalsCount();
          }
        }
      )
      .subscribe();

    return () => {
      clearInterval(interval);
      supabase.removeChannel(approvalsChannel);
    };
  }, [session?.employee_id, session?.role, selectedStoreId]);

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsStoreDropdownOpen(false);
      }
    }

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  useEffect(() => {
    initializeVersionCheck();

    const stopVersionCheck = startVersionCheck(() => {
      setHasNewVersion(true);
    });

    return () => {
      stopVersionCheck();
    };
  }, []);

  async function fetchStore() {
    if (!selectedStoreId) return;
    const { data } = await supabase
      .from('stores')
      .select('*')
      .eq('id', selectedStoreId)
      .maybeSingle();
    if (data) setCurrentStore(data);
  }

  async function fetchAllStores() {
    if (!session?.employee_id) return;

    // Admin can see all stores
    if (session?.role_permission === 'Admin') {
      const { data } = await supabase
        .from('stores')
        .select('*')
        .eq('active', true)
        .order('code');
      if (data) {
        console.log('Admin - Fetched stores:', data);
        setAllStores(data);
      }
      return;
    }

    // Other users see only their assigned stores
    const { data: employeeStores } = await supabase
      .from('employee_stores')
      .select('store_id')
      .eq('employee_id', session.employee_id);

    console.log('Employee stores:', employeeStores);
    const employeeStoreIds = employeeStores?.map(es => es.store_id) || [];

    if (employeeStoreIds.length > 0) {
      const { data } = await supabase
        .from('stores')
        .select('*')
        .in('id', employeeStoreIds)
        .eq('active', true)
        .order('code');
      if (data) {
        console.log('Non-admin - Fetched stores:', data);
        setAllStores(data);
      }
    } else {
      console.log('No employee stores found');
    }
  }

  async function fetchPendingApprovalsCount() {
    if (!session?.employee_id || !selectedStoreId) return;

    try {
      // Determine which function to call based on role
      const isTechnicianOrSupervisor = session.role_permission === 'Technician' || session.role_permission === 'Supervisor';

      if (isTechnicianOrSupervisor) {
        const { data, error } = await supabase.rpc('get_pending_approvals_for_technician', {
          p_employee_id: session.employee_id,
          p_store_id: selectedStoreId,
        });

        if (error) throw error;
        setPendingApprovalsCount(data?.length || 0);
      } else {
        // For Receptionist, Manager, Owner - use management function
        const { data, error } = await supabase.rpc('get_pending_approvals_for_management', {
          p_store_id: selectedStoreId,
        });

        if (error) throw error;
        setPendingApprovalsCount(data?.length || 0);
      }
    } catch (error) {
      console.error('Error fetching pending approvals count:', error);
    }
  }

  function handleStoreChange(storeId: string) {
    selectStore(storeId);
    setIsStoreDropdownOpen(false);
  }

  const handleRefresh = () => {
    window.location.reload();
  };

  const getGoogleRating = () => {
    if (!currentStore) return null;

    const storeName = currentStore.name.toLowerCase();
    if (storeName.includes('riviere')) {
      return { rating: '4.8', reviews: '553' };
    } else if (storeName.includes('maily')) {
      return { rating: '3.9', reviews: '575' };
    } else if (storeName.includes('charlesbourg')) {
      return { rating: '3.9', reviews: '232' };
    }
    return null;
  };

  const googleRating = getGoogleRating();

  const navItems = [
    { id: 'home' as const, label: 'Home', icon: Home },
    { id: 'tickets' as const, label: t('nav.tickets'), icon: Receipt },
    { id: 'approvals' as const, label: 'Approvals', icon: CheckCircle, badge: pendingApprovalsCount },
    { id: 'eod' as const, label: t('nav.eod'), icon: DollarSign },
    { id: 'attendance' as const, label: 'Attendance', icon: Calendar },
    { id: 'technicians' as const, label: t('nav.employees'), icon: Users },
    { id: 'services' as const, label: t('nav.services'), icon: Briefcase },
  ];

  return (
    <div className="min-h-screen bg-gray-50">
      {hasNewVersion && <VersionNotification onRefresh={handleRefresh} />}
      <header className="bg-white border-b border-gray-200 sticky top-0 z-30">
        <div className="px-3 py-2 md:px-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 md:gap-3">
              <button
                onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
                className="md:hidden p-1.5 hover:bg-gray-100 rounded transition-colors"
              >
                {isMobileMenuOpen ? <X className="w-5 h-5 text-gray-700" /> : <Menu className="w-5 h-5 text-gray-700" />}
              </button>
              {currentStore && allStores.length > 0 ? (
                <div className="relative" ref={dropdownRef}>
                  <button
                    onClick={() => setIsStoreDropdownOpen(!isStoreDropdownOpen)}
                    className="inline-flex items-center gap-2 px-3 py-1.5 bg-blue-100 text-blue-700 rounded-lg text-sm font-medium hover:bg-blue-200 transition-colors"
                  >
                    <StoreIcon className="w-4 h-4" />
                    {currentStore.name}
                    <ChevronDown className="w-4 h-4" />
                  </button>
                  {isStoreDropdownOpen && (
                    <div className="absolute top-full left-0 mt-1 bg-white border border-gray-200 rounded-lg shadow-lg py-1 min-w-[200px] z-50">
                      {allStores.map((store) => (
                        <button
                          key={store.id}
                          onClick={() => handleStoreChange(store.id)}
                          className={`w-full text-left px-3 py-2 text-xs hover:bg-gray-50 transition-colors flex items-center gap-2 ${
                            store.id === selectedStoreId ? 'bg-blue-50 text-blue-700 font-medium' : 'text-gray-700'
                          }`}
                        >
                          <StoreIcon className="w-3 h-3" />
                          {store.name}
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              ) : currentStore ? (
                <span className="inline-flex items-center gap-2 px-3 py-1.5 bg-blue-100 text-blue-700 rounded-lg text-sm font-medium">
                  <StoreIcon className="w-4 h-4" />
                  {currentStore.name}
                </span>
              ) : null}
            </div>
            <div className="flex items-center gap-2 md:gap-3">
              {googleRating && (
                <div className="hidden md:flex items-center gap-2 px-2.5 py-1.5 bg-white border border-gray-200 rounded-lg shadow-sm">
                  <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
                    <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
                    <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
                    <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
                  </svg>
                  <Star className="w-4 h-4 fill-yellow-400 text-yellow-400" />
                  <span className="text-xs font-medium text-gray-700">{googleRating.rating} ({googleRating.reviews})</span>
                </div>
              )}
              {session && (
                <button
                  onClick={() => onNavigate('settings')}
                  className="hidden md:flex items-center gap-2 px-2 py-1 text-xs text-gray-700 hover:text-gray-800 hover:bg-gray-100 rounded transition-colors"
                  title={t('nav.settings')}
                >
                  <Settings className="w-3 h-3" />
                  {t('nav.settings')}
                </button>
              )}
              <button
                onClick={logout}
                className="flex items-center gap-2 px-2 py-1 text-xs text-red-700 hover:text-red-800 hover:bg-red-50 rounded transition-colors"
                title={t('actions.logout')}
              >
                <LogOut className="w-3 h-3" />
                <span className="hidden md:inline">{t('actions.logout')}</span>
              </button>
            </div>
          </div>
        </div>
      </header>

      <div className="flex">
        <aside className={`fixed md:sticky md:block w-64 md:w-44 bg-white border-r border-gray-200 min-h-[calc(100vh-49px)] top-[49px] left-0 z-20 transform transition-transform duration-300 ${isMobileMenuOpen ? 'translate-x-0' : '-translate-x-full md:translate-x-0'}`}>
          <nav className="p-2">
            <ul className="space-y-0.5">
              {navItems.map((item) => {
                const Icon = item.icon;
                const isActive = currentPage === item.id;
                const hasAccess = session && session.role && canAccessPage(item.id, session.role);

                if (!hasAccess) return null;

                return (
                  <li key={item.id}>
                    <button
                      onClick={() => {
                        onNavigate(item.id);
                        setIsMobileMenuOpen(false);
                      }}
                      className={`w-full flex items-center gap-2 px-3 py-2 rounded-lg transition-colors text-sm ${
                        isActive
                          ? 'bg-blue-50 text-blue-700 font-medium'
                          : 'text-gray-700 hover:bg-gray-50'
                      }`}
                    >
                      <Icon className="w-4 h-4" />
                      <span className="flex-1 text-left">{item.label}</span>
                      {item.badge !== undefined && item.badge > 0 && (
                        <span className="inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 text-xs font-bold text-white bg-red-600 rounded-full">
                          {item.badge > 9 ? '9+' : item.badge}
                        </span>
                      )}
                    </button>
                  </li>
                );
              })}
            </ul>
            <div className="md:hidden mt-4 pt-4 border-t border-gray-200 px-2">
              {session && (
                <button
                  onClick={() => {
                    onNavigate('settings');
                    setIsMobileMenuOpen(false);
                  }}
                  className="w-full flex items-center gap-2 px-3 py-2 rounded-lg transition-colors text-sm text-gray-700 hover:bg-gray-50"
                >
                  <Settings className="w-4 h-4" />
                  <span>{t('nav.settings')}</span>
                </button>
              )}
            </div>
          </nav>
        </aside>

        {isMobileMenuOpen && (
          <div
            className="fixed inset-0 bg-black bg-opacity-50 z-10 md:hidden"
            onClick={() => setIsMobileMenuOpen(false)}
          />
        )}

        <main className="flex-1 p-2 md:p-3 layout-main">{children}</main>
      </div>
    </div>
  );
}
