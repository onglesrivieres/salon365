import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'http://127.0.0.1:54321';
const supabaseKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

const supabase = createClient(supabaseUrl, supabaseKey);

async function addAllStores() {
  console.log('Adding multiple stores and assigning admin to all...\n');

  // Define the stores to create
  const stores = [
    { name: 'Sans Souci Ongles & Spa', code: 'SS', active: true }
  ];

  // Create stores if they don't exist
  for (const store of stores) {
    const { data, error } = await supabase
      .from('stores')
      .upsert(store, { onConflict: 'code' })
      .select();

    if (error) {
      console.error(`Error creating store ${store.name}:`, error);
    } else {
      console.log(`✓ Store created/verified: ${store.name} (${store.code})`);
    }
  }

  // Get all active stores
  const { data: allStores, error: storesError } = await supabase
    .from('stores')
    .select('id, name, code, active')
    .eq('active', true);

  if (storesError) {
    console.error('Error fetching stores:', storesError);
    return;
  }

  console.log(`\nFound ${allStores.length} active stores:`);
  allStores.forEach(store => {
    console.log(`  - ${store.name} (${store.code})`);
  });

  // Get admin user ID
  const { data: adminUsers, error: adminError } = await supabase
    .from('employees')
    .select('id, display_name')
    .or('role.cs.{Owner},role_permission.eq.Admin');

  if (adminError) {
    console.error('Error fetching admin user:', adminError);
    return;
  }

  // Find the admin user with Owner role
  const adminUser = adminUsers.find(emp => 
    emp.id === '1b053a3a-977f-445c-b09c-71d8e93ef19f'
  );

  if (!adminUser) {
    console.log('Admin user not found');
    return;
  }

  console.log(`\nAssigning admin user "${adminUser.display_name}" to all stores...`);

  // Remove existing store assignments for admin
  await supabase
    .from('employee_stores')
    .delete()
    .eq('employee_id', adminUser.id);

  // Assign admin to all stores
  for (const store of allStores) {
    const { error: assignError } = await supabase
      .from('employee_stores')
      .insert({
        employee_id: adminUser.id,
        store_id: store.id
      });

    if (assignError) {
      console.error(`Error assigning to store ${store.name}:`, assignError);
    } else {
      console.log(`✓ Assigned to ${store.name} (${store.code})`);
    }
  }

  // Verify assignments
  console.log('\nVerifying store access...');
  const { data: assignments, error: verifyError } = await supabase
    .from('employee_stores')
    .select(`
      stores (
        name,
        code,
        active
      )
    `)
    .eq('employee_id', adminUser.id);

  if (verifyError) {
    console.error('Error verifying assignments:', verifyError);
  } else {
    console.log('\nAdmin user has access to:');
    assignments.forEach(assignment => {
      if (assignment.stores) {
        console.log(`  - ${assignment.stores.name} (${assignment.stores.code})`);
      }
    });
  }
}

addAllStores().catch(console.error);