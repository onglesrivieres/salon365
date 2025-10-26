/*
  # Add Day-Specific Opening Hours

  1. Changes to `stores` table
    - Add `opening_hours` JSONB column to store day-specific hours
    - Structure: { "monday": "09:00", "tuesday": "09:00", ... }

  2. Update Functions
    - Update `can_checkin_now` to check day-specific opening time
    
  3. Data Population
    - Set opening hours for existing stores based on their schedules

  4. Notes
    - Ongles Rivière-du-Loup (RIVIERES): Mon-Wed: 9:00-17:30, Thurs-Fri: 9:00-21:00, Sat: 9:00-17:00, Sun: 10:00-17:00
    - Ongles Maily: Mon-Wed: 9:00-17:30, Thurs-Fri: 9:00-19:00, Sat: 9:00-17:00, Sun: 10:00-17:00
    - Ongles Charlesbourg: Will use default 10:00 for all days
*/

-- Add opening_hours JSONB column to stores table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stores' AND column_name = 'opening_hours'
  ) THEN
    ALTER TABLE stores ADD COLUMN opening_hours jsonb;
  END IF;
END $$;

-- Update opening hours for Ongles Rivieres
UPDATE stores 
SET opening_hours = jsonb_build_object(
  'monday', '09:00:00',
  'tuesday', '09:00:00',
  'wednesday', '09:00:00',
  'thursday', '09:00:00',
  'friday', '09:00:00',
  'saturday', '09:00:00',
  'sunday', '10:00:00'
)
WHERE code = 'RIVIERES';

-- Update opening hours for Ongles Maily
UPDATE stores 
SET opening_hours = jsonb_build_object(
  'monday', '09:00:00',
  'tuesday', '09:00:00',
  'wednesday', '09:00:00',
  'thursday', '09:00:00',
  'friday', '09:00:00',
  'saturday', '09:00:00',
  'sunday', '10:00:00'
)
WHERE code = 'MAILY';

-- Update opening hours for Ongles Charlesbourg (default to 10:00 for all days)
UPDATE stores 
SET opening_hours = jsonb_build_object(
  'monday', '10:00:00',
  'tuesday', '10:00:00',
  'wednesday', '10:00:00',
  'thursday', '10:00:00',
  'friday', '10:00:00',
  'saturday', '10:00:00',
  'sunday', '10:00:00'
)
WHERE code = 'CHARLESBOURG';

-- Update can_checkin_now function to use day-specific opening times
CREATE OR REPLACE FUNCTION can_checkin_now(p_store_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_opening_hours jsonb;
  v_opening_time time;
  v_current_time time;
  v_current_day text;
  v_check_in_window_start time;
BEGIN
  -- Get current day of week (lowercase)
  v_current_day := lower(to_char(NOW() AT TIME ZONE 'America/New_York', 'Day'));
  v_current_day := trim(v_current_day);

  -- Get store opening hours
  SELECT opening_hours INTO v_opening_hours
  FROM stores
  WHERE id = p_store_id;

  -- If opening_hours is set, use day-specific time
  IF v_opening_hours IS NOT NULL THEN
    v_opening_time := (v_opening_hours->>v_current_day)::time;
  END IF;

  -- Fallback to opening_time column if opening_hours not set
  IF v_opening_time IS NULL THEN
    SELECT opening_time INTO v_opening_time
    FROM stores
    WHERE id = p_store_id;
  END IF;

  IF v_opening_time IS NULL THEN
    RETURN true; -- Allow if no opening time set
  END IF;

  -- Get current time in store's timezone (Eastern Time)
  v_current_time := (NOW() AT TIME ZONE 'America/New_York')::time;

  -- Calculate check-in window start (15 minutes before opening)
  v_check_in_window_start := v_opening_time - interval '15 minutes';

  -- Allow check-in if current time is within window
  RETURN v_current_time >= v_check_in_window_start;
END;
$$;