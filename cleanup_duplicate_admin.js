import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'http://127.0.0.1:54321';
const supabaseKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

const supabase = createClient(supabaseUrl, supabaseKey);

async function cleanupDuplicateAdmin() {
  console.log('=== CLEANING UP DUPLICATE ADMIN USERS ===\n');

  // Get all admin users
  const { data: adminUsers, error: userError } = await supabase
    .from('employees')
    .select('id, display_name, role, role_permission, pin_code_hash')
    .or('role.cs.{Owner},role_permission.eq.Admin');

  if (userError) {
    console.error('Error fetching admin users:', userError);
    return;
  }

  console.log('Found admin users:');
  adminUsers.forEach((user, index) => {
    console.log(`${index + 1}. ID: ${user.id}`);
    console.log(`   Name: ${user.display_name}`);
    console.log(`   Role: ${user.role}`);
    console.log(`   Role Permission: ${user.role_permission}`);
    console.log(`   Has PIN: ${user.pin_code_hash ? 'Yes' : 'No'}`);
    console.log('');
  });

  // Keep only the user with both Owner and Manager roles
  const correctAdmin = adminUsers.find(user => 
    user.role.includes('Owner') && user.role.includes('Manager')
  );

  const duplicateAdmins = adminUsers.filter(user => user.id !== correctAdmin?.id);

  if (duplicateAdmins.length > 0) {
    console.log(`Removing ${duplicateAdmins.length} duplicate admin user(s)...`);

    for (const duplicate of duplicateAdmins) {
      // Remove store assignments first
      await supabase
        .from('employee_stores')
        .delete()
        .eq('employee_id', duplicate.id);

      // Remove the duplicate user
      const { error: deleteError } = await supabase
        .from('employees')
        .delete()
        .eq('id', duplicate.id);

      if (deleteError) {
        console.error(`Error removing duplicate ${duplicate.display_name}:`, deleteError);
      } else {
        console.log(`✓ Removed duplicate admin: ${duplicate.display_name}`);
      }
    }
  } else {
    console.log('No duplicate admin users found.');
  }

  console.log('\n=== FINAL ADMIN USER ===');

  // Verify the correct admin user
  const { data: finalAdmin, error: finalError } = await supabase
    .from('employees')
    .select(`
      id,
      display_name,
      role,
      role_permission,
      can_reset_pin,
      employee_stores (
        stores (
          name,
          code,
          active
        )
      )
    `)
    .eq('id', correctAdmin.id)
    .single();

  if (finalError) {
    console.error('Error fetching final admin:', finalError);
    return;
  }

  console.log('Admin user details:');
  console.log(`  ID: ${finalAdmin.id}`);
  console.log(`  Name: ${finalAdmin.display_name}`);
  console.log(`  Role: ${finalAdmin.role}`);
  console.log(`  Role Permission: ${finalAdmin.role_permission}`);
  console.log(`  Can Reset PIN: ${finalAdmin.can_reset_pin}`);
  console.log('  Store Access:');
  
  if (finalAdmin.employee_stores && finalAdmin.employee_stores.length > 0) {
    finalAdmin.employee_stores.forEach(es => {
      if (es.stores) {
        console.log(`    - ${es.stores.name} (${es.stores.code})`);
      }
    });
  } else {
    console.log('    No store access assigned');
  }

  // Test PIN verification
  console.log('\nTesting PIN verification...');
  const { data: pinData, error: pinError } = await supabase.rpc('verify_employee_pin', {
    pin_input: '8228'
  });

  if (pinError) {
    console.error('PIN verification error:', pinError);
  } else if (pinData && pinData.length > 0) {
    console.log('✓ PIN 8228 successfully authenticates:');
    console.log(`  User: ${pinData[0].display_name}`);
    console.log(`  ID: ${pinData[0].employee_id}`);
  } else {
    console.log('✗ PIN 8228 does not authenticate any user');
  }
}

cleanupDuplicateAdmin().catch(console.error);