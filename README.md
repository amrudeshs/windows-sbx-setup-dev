# Docker Sandboxes (`sbx`) — Team Config

The final proposed setup for a team of **Windows developers** who build on an **on-prem Linux
server** with a **shared database**, each running their own **Docker Compose** stack in an isolated
sandbox. This file is the entry point; the numbered docs explain how it works.

> **New here?** Start with the one-page [overview.html](overview.html) (approach, benefits, simple
> setup), then come back for the details.

> **Source of truth:** [docs.docker.com/ai/sandboxes](https://docs.docker.com/ai/sandboxes/)
> (captured October 2026). `sbx` moves fast — v3 kits need `sbx` ≥ 0.45. Verify against the live docs
> before rollout.

---

## The configuration

| Piece | Where it runs |
| --- | --- |
| `sbx` (Docker Sandboxes) | Each Windows 11 developer laptop |
| Agent (OpenCode) + app Compose stack | Inside each developer's Linux microVM sandbox |
| Shared Postgres | On the on-prem Linux server, under the host Docker Engine |

- Every sandbox is a **Linux microVM with its own Docker daemon** → devs run `docker compose`
  independently and cannot affect the host or each other.
- The **shared DB** is reached over the LAN: `sbx policy allow network <db-host>:5432`.
- No WSL2 needed. Enabling the sandbox runtime needs a **one-time admin action** per laptop.
- **Developers have no shell account on the server.** Code and editors live on the laptop; the
  server only runs Postgres. (Running `sbx` on the server instead is a documented
  [alternative](01-architecture.md#the-alternatives), not part of this setup.)

### Config files

| File | Purpose |
| --- | --- |
| [`config/sbxenv.yaml`](config/sbxenv.yaml) | Per-project environment (agent, workspace, resources, ports, DB URL template). |
| [`config/shared-db.compose.yaml`](config/shared-db.compose.yaml) | Shared Postgres for the Linux server (TLS, pg_hba, LAN-bound). |
| [`config/postgres/pg_hba.conf`](config/postgres/pg_hba.conf) | Client auth for the shared Postgres: TLS + SCRAM from the dev subnet only. |
| [`config/db-baseline.sql`](config/db-baseline.sql) | One-time Postgres hardening (revoke default `PUBLIC` access). |
| [`config/provision-developer.sql`](config/provision-developer.sql) | Create one isolated database + role per developer. |
| [`config/deprovision-developer.sql`](config/deprovision-developer.sql) | Offboarding: drop a developer's database + role. |
| [`config/allowlist.sh`](config/allowlist.sh) | Network policy rules (DB, chosen providers, registries, Git). |
| [`config/opencode.json`](config/opencode.json) | Optional: point OpenCode at a local model server. |

### Explanation docs

| File | What it covers |
| --- | --- |
| [01-architecture.md](01-architecture.md) | The recommended system, requirement mapping, and the alternatives. |
| [02-sandboxes-explained.md](02-sandboxes-explained.md) | What `sbx` is: microVM isolation, Linux images, lifecycle, comparisons. |
| [03-workspaces.md](03-workspaces.md) | Mounting directories, multiple workspaces, mountless, clone mode, naming. |
| [04-environments-kits-and-templates.md](04-environments-kits-and-templates.md) | Agents, kits, `sbxenv.yaml`, templates, resource limits. |
| [05-docker-compose-and-shared-db.md](05-docker-compose-and-shared-db.md) | Compose inside a sandbox and reaching the shared DB. |
| [06-networking-and-policy.md](06-networking-and-policy.md) | Deny-by-default egress, `host.docker.internal`, policy rules, proxies. |
| [07-windows-and-admin.md](07-windows-and-admin.md) | Windows prerequisites, the one-time admin requirement, MDM deployment. |
| [08-performance.md](08-performance.md) | Speed vs native, where overhead is, mitigations. |
| [09-security-and-guardrails.md](09-security-and-guardrails.md) | Isolation layers and the guardrails that make it safe. |
| [10-runbook-and-examples.md](10-runbook-and-examples.md) | Onboarding checklist, DB provisioning/backup/offboarding, cheat sheet, cleanup. |
| [11-troubleshooting.md](11-troubleshooting.md) | DB unreachable, blocked requests, disk full, version problems. |

---

## How to use it

### 1. One-time laptop setup (Windows 11)

IT enables the sandbox runtime once per machine (elevated, reboot):

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
```

Then the developer installs and signs in (no admin):

```powershell
winget install -h Docker.sbx
sbx login
```

Store the model-provider credential:

```sh
sbx secret set anthropic        # or openai / openrouter / google / xai
```

### 2. Server: shared database (ops, once)

Prepare TLS certificates in `config/certs/` and edit the subnet in `config/postgres/pg_hba.conf`
([details](10-runbook-and-examples.md#b-shared-postgres-on-the-linux-server)), then:

```sh
cd config
export POSTGRES_PASSWORD=<strong-secret>   # ops only; never given to developers
export DB_BIND_ADDR=<server-lan-ip>
docker compose -f shared-db.compose.yaml up -d
docker exec -i shared-postgres psql -U postgres -v ON_ERROR_STOP=1 < db-baseline.sql   # once
```

Per developer (generates an isolated database `<dev>_app` and a non-superuser role):

```sh
docker exec -i shared-postgres psql -U postgres -v ON_ERROR_STOP=1 \
  -v dev=alice -v pw="$(openssl rand -base64 24)" < provision-developer.sql
```

### 3. Per project: copy the environment file

Copy `config/sbxenv.yaml` into a folder **beside** the project (not inside a mounted workspace),
fill in the name, `DATABASE_URL`, and ports, then:

```sh
sbx env plan          # preview
sbx env run           # create + attach
```

Day-to-day:

```sh
sbx env run                       # reattach / restart (config changes need `sbx env rm` + recreate)
sbx exec -it <sandbox> bash       # shell inside the sandbox
sbx ports <sandbox> --publish 8080:3000
sbx env rm                        # destroy when done
```

### 4. Network policy

Pick the **Locked Down** preset at first run, then allow exactly what the project needs:

```sh
sh config/allowlist.sh 10.0.0.5 anthropic     # <db-host> <providers>
sbx policy ls
```

Then confirm the database path works before anything else ([troubleshooting](11-troubleshooting.md)):

```sh
sbx exec -it <sandbox> bash
# inside the sandbox:
timeout 5 bash -c '</dev/tcp/10.0.0.5/5432' && echo "DB port reachable"
```

### 5. Editing

Everything happens on the laptop: open the project folder in your editor on Windows, and run
`sbx env run` in a terminal for the agent. The sandbox mounts that folder. Do not point your editor
at files on the server and do not mount network shares as a workspace.

---

## Key gotchas

- **`host.docker.internal` = the machine running `sbx`** (the laptop). The **shared DB is remote** —
  reach it by `<db-host>:5432`, not `host.docker.internal`.
- **The DB password is visible to the agent.** `sbx secret` only injects HTTP headers, so it cannot
  protect a Postgres credential. Use the per-developer role, TLS, and never reuse the password.
  See [09](09-security-and-guardrails.md#secrets).
- **Agents can be steered by what they read** (prompt injection). Prefer
  [clone mode](03-workspaces.md#clone-mode-read-only-source--private-clone) for code you don't fully
  trust, and keep the allowlist short.
- **Mount source only.** Keep `node_modules`, `.venv`, build output off the host mount (put them on
  the sandbox disk) or file I/O gets slow.
- **DB tenancy:** one database + role per developer, no shared superuser, `PUBLIC` access revoked.
- **First run in a new sandbox is cold** (image pull + build cache); later runs are fast.

## Docs

<https://docs.docker.com/ai/sandboxes/> · CLI: <https://docs.docker.com/reference/cli/sbx/>
