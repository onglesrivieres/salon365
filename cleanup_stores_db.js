import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'http://127.0.0.1:54321';
const supabaseKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

const supabase = createClient(supabaseUrl, supabaseKey);

async function removeUnwantedStores() {
  console.log('🧹 Removing unwanted stores from database...');
  
  try {
    // Step 1: Get unwanted store IDs
    const { data: unwantedStores, error: fetchError } = await supabase
      .from('stores')
      .select('id, name')
      .in('name', ['Ongles Maily', 'Ongles Charlesbourg', 'Ongles Rivières']);

    if (fetchError) {
      console.error('Error fetching unwanted stores:', fetchError);
      return;
    }

    if (!unwantedStores || unwantedStores.length === 0) {
      console.log('✅ No unwanted stores found in database.');
    } else {
      console.log(`📋 Found ${unwantedStores.length} unwanted stores:`);
      unwantedStores.forEach(store => {
        console.log(`   - ${store.name} (${store.id})`);
      });

      const unwantedStoreIds = unwantedStores.map(store => store.id);

      // Step 2: Delete store-specific service configurations for unwanted stores
      const { error: serviceError } = await supabase
        .from('store_services')
        .delete()
        .in('store_id', unwantedStoreIds);

      if (serviceError) {
        console.error('Error deleting store services:', serviceError);
      } else {
        console.log('✅ Deleted store-specific service configurations');
      }

      // Step 3: Delete employee-store assignments for unwanted stores
      const { error: assignmentError } = await supabase
        .from('employee_stores')
        .delete()
        .in('store_id', unwantedStoreIds);

      if (assignmentError) {
        console.error('Error deleting employee store assignments:', assignmentError);
      } else {
        console.log('✅ Deleted employee-store assignments');
      }

      // Step 4: Delete the unwanted stores themselves
      const { error: deleteError } = await supabase
        .from('stores')
        .delete()
        .in('name', ['Ongles Maily', 'Ongles Charlesbourg', 'Ongles Rivières']);

      if (deleteError) {
        console.error('Error deleting stores:', deleteError);
      } else {
        console.log('✅ Deleted unwanted stores from database');
      }
    }

    // Step 5: Verify only Sans Souci Ongles & Spa remains
    const { data: remainingStores, error: verifyError } = await supabase
      .from('stores')
      .select('name, code, active')
      .eq('active', true)
      .order('name');

    if (verifyError) {
      console.error('Error verifying remaining stores:', verifyError);
    } else {
      console.log('\n📊 Remaining active stores:');
      if (remainingStores && remainingStores.length > 0) {
        remainingStores.forEach(store => {
          console.log(`   ✓ ${store.name} (${store.code})`);
        });
        console.log(`\n✅ Success! Total active stores: ${remainingStores.length}`);
      } else {
        console.log('❌ No active stores found!');
      }
    }

  } catch (error) {
    console.error('Unexpected error:', error);
  }
}

removeUnwantedStores();