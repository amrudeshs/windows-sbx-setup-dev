# Docker Sandboxes (`sbx`) — Team Config

The final proposed setup for a team of **Windows developers** who build on an **on-prem Linux
server** with a **shared database**, each running their own **Docker Compose** stack in an isolated
sandbox. This file is the entry point; the numbered docs explain how it works.

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

### Config files

| File | Purpose |
| --- | --- |
| [`config/sbxenv.yaml`](config/sbxenv.yaml) | Per-project environment (agent, workspace, resources, ports, DB URL). |
| [`config/shared-db.compose.yaml`](config/shared-db.compose.yaml) | Shared Postgres for the Linux server. |
| [`config/allowlist.sh`](config/allowlist.sh) | Network policy rules (providers, registries, shared DB). |
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
| [10-runbook-and-examples.md](10-runbook-and-examples.md) | Onboarding checklist, shared Postgres SQL, cheat sheet, cleanup. |

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

```sh
cd config
POSTGRES_PASSWORD=<strong-secret> docker compose -f shared-db.compose.yaml up -d
```

Then create one database + role per developer:

```sql
CREATE ROLE alice LOGIN PASSWORD 'alice-strong-password' CONNECTION LIMIT 20;
CREATE DATABASE alice_app OWNER alice;
```

### 3. Per project: copy the environment file

Copy `config/sbxenv.yaml` into a folder **beside** the project (not inside a mounted workspace),
edit the name, DB URL, and ports, then:

```sh
sbx env plan          # preview
sbx env run           # create + attach
```

Day-to-day:

```sh
sbx env run                       # reattach / restart the environment
sbx exec -it <sandbox> bash       # shell inside the sandbox
sbx ports <sandbox> --publish 8080:3000
sbx env rm                        # destroy when done
```

### 4. Network policy

```sh
sh config/allowlist.sh 10.0.0.5     # pass your DB host
sbx policy ls
```

### 5. Editing

VS Code **Remote-SSH** to the project directory on the server for files; run `sbx env run` in a
terminal for the agent. (Or keep everything on the laptop and treat the sandbox as the build/run
environment.)

---

## Key gotchas

- **`host.docker.internal` = the machine running `sbx`** (the laptop). The **shared DB is remote** —
  reach it by `<db-host>:5432`, not `host.docker.internal`.
- **Mount source only.** Keep `node_modules`, `.venv`, build output off the host mount (put them on
  the sandbox disk) or file I/O gets slow.
- **Never add devs to the host `docker` group** — that is root-equivalent and defeats the isolation.
- **DB tenancy:** one database + role per developer, no shared superuser.
- **First run in a new sandbox is cold** (image pull + build cache); later runs are fast.

## Docs

<https://docs.docker.com/ai/sandboxes/> · CLI: <https://docs.docker.com/reference/cli/sbx/>
