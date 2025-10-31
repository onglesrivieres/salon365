import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'http://127.0.0.1:54321';
const supabaseKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

const supabase = createClient(supabaseUrl, supabaseKey);

async function debugPIN() {
  console.log('=== DEBUGGING PIN VERIFICATION ===\n');

  // Get admin user details
  const { data: users, error: userError } = await supabase
    .from('employees')
    .select('id, display_name, pin_code_hash, status')
    .eq('id', '1b053a3a-977f-445c-b09c-71d8e93ef19f');

  if (userError) {
    console.error('Error fetching user:', userError);
    return;
  }

  console.log('Admin user details:');
  console.log(users[0]);
  console.log('');

  // Test the verify_employee_pin function (used for login)
  console.log('Testing verify_employee_pin function (used for login)...');
  const { data: loginData, error: loginError } = await supabase.rpc('verify_employee_pin', {
    pin_input: '8228'
  });

  if (loginError) {
    console.error('Login function error:', loginError);
  } else {
    console.log('Login function result:', loginData);
  }
  console.log('');

  // Test the verify_employee_pin_by_id function
  console.log('Testing verify_employee_pin_by_id function...');
  const { data: byIdData, error: byIdError } = await supabase.rpc('verify_employee_pin_by_id', {
    emp_id: '1b053a3a-977f-445c-b09c-71d8e93ef19f',
    pin_code: '8228'
  });

  if (byIdError) {
    console.error('By ID function error:', byIdError);
  } else {
    console.log('By ID function result:', byIdData);
  }
  console.log('');

  // Check what the actual stored hash looks like
  if (users[0].pin_code_hash) {
    console.log('Stored PIN hash:', users[0].pin_code_hash);
    console.log('Hash length:', users[0].pin_code_hash.length);
  }
}

debugPIN().catch(console.error);