/*
  # Create Session Management Functions

  ## Overview
  Creates database functions to manage user sessions, preferences, and application state.

  ## Functions

  ### create_user_session
  Creates a new session for an employee after successful PIN authentication.
  - Parameters: emp_id (uuid), device_info (jsonb)
  - Returns: session record with token
  - Auto-expires after 5 minutes of inactivity

  ### validate_and_refresh_session
  Validates a session token and updates last activity time.
  - Parameters: session_token (text)
  - Returns: employee info if session is valid, null if expired/invalid
  - Extends session expiration on successful validation

  ### cleanup_expired_sessions
  Removes all expired sessions from the database.
  - Called automatically via cron job
  - Deletes sessions where expires_at < now()

  ### get_or_create_user_preferences
  Gets existing preferences or creates default preferences for an employee.
  - Parameters: emp_id (uuid)
  - Returns: user preferences record

  ### update_user_preference
  Updates a specific preference field for an employee.
  - Parameters: emp_id (uuid), pref_key (text), pref_value (text)
  - Returns: success boolean

  ### get_application_state
  Gets application state value for an employee and optional device.
  - Parameters: emp_id (uuid), state_key (text), device_id (text, optional)
  - Returns: state_value

  ### set_application_state
  Sets or updates application state for an employee and optional device.
  - Parameters: emp_id (uuid), state_key (text), state_value (text), device_id (text, optional)
  - Returns: success boolean
*/

-- Function to create a new user session
CREATE OR REPLACE FUNCTION create_user_session(
  emp_id uuid,
  device_info jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  session_id uuid,
  session_token text,
  expires_at timestamptz
) AS $$
DECLARE
  v_token text;
  v_expires_at timestamptz;
  v_session_id uuid;
BEGIN
  -- Generate a random session token
  v_token := encode(gen_random_bytes(32), 'base64');
  
  -- Set expiration to 5 minutes from now
  v_expires_at := now() + interval '5 minutes';
  
  -- Insert the session
  INSERT INTO user_sessions (employee_id, session_token, device_info, expires_at)
  VALUES (emp_id, v_token, device_info, v_expires_at)
  RETURNING id INTO v_session_id;
  
  -- Return session details
  RETURN QUERY SELECT v_session_id, v_token, v_expires_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to validate and refresh a session
CREATE OR REPLACE FUNCTION validate_and_refresh_session(
  p_session_token text
)
RETURNS TABLE (
  employee_id uuid,
  display_name text,
  role text[],
  role_permission text,
  can_reset_pin boolean,
  store_id uuid
) AS $$
DECLARE
  v_session record;
BEGIN
  -- Get session details
  SELECT us.employee_id, us.expires_at
  INTO v_session
  FROM user_sessions us
  WHERE us.session_token = p_session_token;
  
  -- Check if session exists and is not expired
  IF v_session IS NULL OR v_session.expires_at < now() THEN
    -- Session invalid or expired
    IF v_session IS NOT NULL THEN
      -- Clean up expired session
      DELETE FROM user_sessions WHERE session_token = p_session_token;
    END IF;
    RETURN;
  END IF;
  
  -- Update last activity and extend expiration
  UPDATE user_sessions
  SET 
    last_activity_at = now(),
    expires_at = now() + interval '5 minutes'
  WHERE session_token = p_session_token;
  
  -- Return employee details
  RETURN QUERY
  SELECT 
    e.id,
    e.display_name,
    e.role,
    COALESCE(e.role_permission, 'Technician'::text) as role_permission,
    COALESCE(e.can_reset_pin, false) as can_reset_pin,
    (
      SELECT es.store_id 
      FROM employee_stores es 
      WHERE es.employee_id = e.id 
      LIMIT 1
    ) as store_id
  FROM employees e
  WHERE e.id = v_session.employee_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to cleanup expired sessions
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS integer AS $$
DECLARE
  v_deleted_count integer;
BEGIN
  DELETE FROM user_sessions
  WHERE expires_at < now();
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  
  RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get or create user preferences
CREATE OR REPLACE FUNCTION get_or_create_user_preferences(
  emp_id uuid
)
RETURNS TABLE (
  employee_id uuid,
  locale text,
  default_store_id uuid,
  settings jsonb
) AS $$
BEGIN
  -- Try to get existing preferences
  RETURN QUERY
  SELECT up.employee_id, up.locale, up.default_store_id, up.settings
  FROM user_preferences up
  WHERE up.employee_id = emp_id;
  
  -- If no preferences exist, create default ones
  IF NOT FOUND THEN
    INSERT INTO user_preferences (employee_id, locale, settings)
    VALUES (emp_id, 'en', '{}'::jsonb)
    ON CONFLICT (employee_id) DO NOTHING;
    
    RETURN QUERY
    SELECT up.employee_id, up.locale, up.default_store_id, up.settings
    FROM user_preferences up
    WHERE up.employee_id = emp_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update user preferences
CREATE OR REPLACE FUNCTION update_user_preferences(
  emp_id uuid,
  p_locale text DEFAULT NULL,
  p_default_store_id uuid DEFAULT NULL,
  p_settings jsonb DEFAULT NULL
)
RETURNS boolean AS $$
BEGIN
  -- Upsert preferences
  INSERT INTO user_preferences (employee_id, locale, default_store_id, settings, updated_at)
  VALUES (
    emp_id, 
    COALESCE(p_locale, 'en'), 
    p_default_store_id,
    COALESCE(p_settings, '{}'::jsonb),
    now()
  )
  ON CONFLICT (employee_id) 
  DO UPDATE SET
    locale = COALESCE(p_locale, user_preferences.locale),
    default_store_id = COALESCE(p_default_store_id, user_preferences.default_store_id),
    settings = COALESCE(p_settings, user_preferences.settings),
    updated_at = now();
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get application state
CREATE OR REPLACE FUNCTION get_application_state(
  emp_id uuid,
  state_key text,
  device_id text DEFAULT ''
)
RETURNS text AS $$
DECLARE
  v_state_value text;
BEGIN
  SELECT state_value INTO v_state_value
  FROM application_state
  WHERE employee_id = emp_id 
    AND application_state.state_key = get_application_state.state_key
    AND application_state.device_id = get_application_state.device_id;
  
  RETURN v_state_value;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to set application state
CREATE OR REPLACE FUNCTION set_application_state(
  emp_id uuid,
  state_key text,
  state_value text,
  device_id text DEFAULT ''
)
RETURNS boolean AS $$
BEGIN
  INSERT INTO application_state (employee_id, state_key, state_value, device_id, updated_at)
  VALUES (emp_id, state_key, state_value, device_id, now())
  ON CONFLICT ON CONSTRAINT application_state_pkey
  DO UPDATE SET
    state_value = EXCLUDED.state_value,
    updated_at = now()
  WHERE application_state.employee_id = emp_id 
    AND application_state.state_key = set_application_state.state_key
    AND application_state.device_id = set_application_state.device_id;
    
  IF NOT FOUND THEN
    -- If no conflict, try to update existing record
    UPDATE application_state
    SET state_value = set_application_state.state_value, updated_at = now()
    WHERE employee_id = emp_id 
      AND application_state.state_key = set_application_state.state_key
      AND application_state.device_id = set_application_state.device_id;
      
    IF NOT FOUND THEN
      -- Record was inserted, return true
      RETURN true;
    END IF;
  END IF;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;