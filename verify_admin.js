import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'http://127.0.0.1:54321';
const supabaseKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

const supabase = createClient(supabaseUrl, supabaseKey);

async function verifyAdmin() {
  console.log('Verifying admin user...\n');

  // Get admin user with store access
  const { data: employees, error: empError } = await supabase
    .from('employees')
    .select(`
      id,
      legal_name,
      display_name,
      role,
      role_permission,
      status,
      can_reset_pin,
      pin_code_hash,
      employee_stores (
        stores (
          name,
          code,
          active
        )
      )
    `)
    .or('role.cs.{Owner},role_permission.eq.Admin');

  if (empError) {
    console.error('Error fetching admin user:', empError);
    return;
  }

  if (!employees || employees.length === 0) {
    console.log('No admin user found');
    return;
  }

  employees.forEach(emp => {
    console.log('Admin User Found:');
    console.log('  ID:', emp.id);
    console.log('  Legal Name:', emp.legal_name);
    console.log('  Display Name:', emp.display_name);
    console.log('  Role:', emp.role);
    console.log('  Role Permission:', emp.role_permission);
    console.log('  Status:', emp.status);
    console.log('  Can Reset PIN:', emp.can_reset_pin);
    console.log('  PIN Status:', emp.pin_code_hash ? 'PIN is set' : 'PIN is NOT set');
    console.log('  Store Access:');
    
    if (emp.employee_stores && emp.employee_stores.length > 0) {
      emp.employee_stores.forEach(es => {
        if (es.stores) {
          console.log(`    - ${es.stores.name} (${es.stores.code}) - ${es.stores.active ? 'Active' : 'Inactive'}`);
        }
      });
    } else {
      console.log('    No store access assigned');
    }
    console.log('');
  });

  // Verify PIN authentication
  console.log('Testing PIN authentication...');
  
  // First check what PIN verification functions are available
  const { data: funcData, error: funcError } = await supabase
    .rpc('verify_employee_pin_by_id', {
      emp_id: '1b053a3a-977f-445c-b09c-71d8e93ef19f',
      pin_code: '8228'
    });

  if (funcError) {
    console.error('PIN verification error:', funcError);
  } else {
    console.log('✓ PIN verification result:', funcData);
  }
}

verifyAdmin().catch(console.error);