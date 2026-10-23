-- Create one isolated database + role for a developer. Run from the server, as the superuser:
--
--   docker exec -i shared-postgres psql -U postgres -v ON_ERROR_STOP=1 \
--     -v dev=alice -v pw='<generated-password>' < provision-developer.sql
--
-- Creates role "alice" and database "alice_app". The role is not a superuser and cannot create
-- roles or databases, and nobody else can connect to its database.
-- Generate the password (e.g. `openssl rand -base64 24`) and hand it to the developer once.

\set db :dev _app

CREATE ROLE :"dev" LOGIN PASSWORD :'pw'
  CONNECTION LIMIT 20 NOSUPERUSER NOCREATEDB NOCREATEROLE;

-- Runaway queries and forgotten transactions are the usual way one tenant hurts the others.
ALTER ROLE :"dev" SET statement_timeout = '5min';
ALTER ROLE :"dev" SET idle_in_transaction_session_timeout = '10min';

CREATE DATABASE :"db" OWNER :"dev";
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db" TO :"dev";
