DO $$
DECLARE
  view_name text := '%<name>s';
  view_type text;
BEGIN
  SELECT relkind INTO view_type
  FROM pg_class
  WHERE relname = view_name
    AND relnamespace = 'public'::regnamespace;

  IF view_type = 'v' THEN
    EXECUTE format('DROP VIEW %%I;', view_name);
  ELSIF view_type = 'm' THEN
    EXECUTE format('DROP MATERIALIZED VIEW %%I;', view_name);
  ELSE
    RAISE EXCEPTION 'Object "%%" is not a view or materialized view', view_name;
  END IF;
END $$;
