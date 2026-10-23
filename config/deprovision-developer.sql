-- Remove a developer's database and role (offboarding). Run from the server, as the superuser:
--
--   docker exec -i shared-postgres psql -U postgres -v ON_ERROR_STOP=1 \
--     -v dev=alice < deprovision-developer.sql
--
-- This DESTROYS the developer's data. Take a dump first if it may be needed:
--   docker exec shared-postgres pg_dump -U postgres -Fc alice_app > alice_app.dump

\set db :dev _app

SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = :'db';
DROP DATABASE :"db";
DROP ROLE :"dev";
