export type RolePermission = 'Admin' | 'Receptionist' | 'Technician' | 'Supervisor';
export type Role = 'Technician' | 'Receptionist' | 'Supervisor' | 'Manager' | 'Owner' | 'Spa Expert';

export interface PermissionCheck {
  canView: boolean;
  canCreate: boolean;
  canEdit: boolean;
  canDelete: boolean;
  message?: string;
}

function hasAnyRole(roles: Role[] | RolePermission, allowedRoles: string[]): boolean {
  if (typeof roles === 'string') {
    return allowedRoles.includes(roles);
  }
  return roles.some(role => allowedRoles.includes(role));
}

export const Permissions = {
  tickets: {
    canView: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Technician', 'Spa Expert', 'Supervisor', 'Manager', 'Owner']);
    },
    canCreate: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
    canEdit: (roles: Role[] | RolePermission, isClosed: boolean, isApproved?: boolean): boolean => {
      if (hasAnyRole(roles, ['Admin', 'Owner'])) return true;
      if (hasAnyRole(roles, ['Receptionist', 'Supervisor', 'Manager'])) return !isClosed && !isApproved;
      return false;
    },
    canEditNotes: (roles: Role[] | RolePermission, isClosed: boolean): boolean => {
      if (hasAnyRole(roles, ['Admin', 'Owner'])) return true;
      if (hasAnyRole(roles, ['Receptionist', 'Supervisor', 'Manager'])) return !isClosed;
      if (hasAnyRole(roles, ['Technician', 'Spa Expert'])) return !isClosed;
      return false;
    },
    canDelete: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
    canViewAll: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
    canClose: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
    canReopen: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
    canApprove: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Technician', 'Spa Expert', 'Supervisor', 'Owner']);
    },
    canViewPendingApprovals: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Technician', 'Spa Expert', 'Supervisor', 'Owner']);
    },
    canReviewRejected: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Owner']);
    },
  },

  endOfDay: {
    canView: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Technician', 'Spa Expert', 'Supervisor', 'Manager', 'Owner']);
    },
    canViewAll: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
    canExport: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
  },

  employees: {
    canView: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
    canCreate: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Owner']);
    },
    canEdit: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Owner']);
    },
    canDelete: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Owner']);
    },
    canResetPIN: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Supervisor', 'Manager', 'Owner']);
    },
    canAssignRoles: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Owner']);
    },
  },

  services: {
    canView: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
    canCreate: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Owner']);
    },
    canEdit: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Owner']);
    },
    canDelete: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Owner']);
    },
  },

  profile: {
    canChangePIN: (roles: Role[] | RolePermission): boolean => {
      return true;
    },
  },

  attendance: {
    canView: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Technician', 'Spa Expert', 'Supervisor', 'Manager', 'Owner']);
    },
    canComment: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Technician', 'Spa Expert', 'Supervisor', 'Manager', 'Owner']);
    },
    canExport: (roles: Role[] | RolePermission): boolean => {
      return hasAnyRole(roles, ['Admin', 'Receptionist', 'Supervisor', 'Manager', 'Owner']);
    },
  },
};

export function getPermissionMessage(
  action: string,
  requiredRole: RolePermission
): string {
  return `Permission required: ${requiredRole} only - ${action}`;
}

export function canAccessPage(
  page: 'tickets' | 'eod' | 'technicians' | 'services' | 'profile' | 'attendance' | 'approvals',
  roles: Role[] | RolePermission
): boolean {
  switch (page) {
    case 'tickets':
      return Permissions.tickets.canView(roles);
    case 'eod':
      return Permissions.endOfDay.canView(roles);
    case 'technicians':
      return Permissions.employees.canView(roles);
    case 'services':
      return Permissions.services.canView(roles);
    case 'profile':
      return true;
    case 'attendance':
      return Permissions.attendance.canView(roles);
    case 'approvals':
      return Permissions.tickets.canViewPendingApprovals(roles);
    default:
      return false;
  }
}

export function getAccessiblePages(roles: Role[] | RolePermission): string[] {
  const pages: string[] = ['tickets', 'profile'];

  if (Permissions.tickets.canViewPendingApprovals(roles)) {
    pages.push('approvals');
  }

  if (Permissions.endOfDay.canView(roles)) {
    pages.push('eod');
  }

  if (Permissions.attendance.canView(roles)) {
    pages.push('attendance');
  }

  if (Permissions.employees.canView(roles)) {
    pages.push('technicians');
  }

  if (Permissions.services.canView(roles)) {
    pages.push('services');
  }

  return pages;
}
