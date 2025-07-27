DO $$
DECLARE
  func_name text := '%<name>s';
  func_record record;
BEGIN
  FOR func_record IN
    SELECT pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = func_name
      AND n.nspname = 'public'
  LOOP
    EXECUTE format('DROP FUNCTION public.%%I(%%s);', func_name, func_record.args);
  END LOOP;
END $$;
