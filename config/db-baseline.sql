-- Run ONCE on a fresh shared Postgres, as the superuser, from the server:
--   docker exec -i shared-postgres psql -U postgres -v ON_ERROR_STOP=1 < db-baseline.sql
--
-- Postgres grants CONNECT on every database to PUBLIC by default, so without this a developer
-- role could connect to the maintenance databases (and, before provisioning revokes it, to
-- anyone else's database).

REVOKE CONNECT ON DATABASE postgres  FROM PUBLIC;
REVOKE CONNECT ON DATABASE template1 FROM PUBLIC;

-- Databases created from template1 from now on start with no PUBLIC access to the public schema.
\connect template1
REVOKE ALL ON SCHEMA public FROM PUBLIC;
