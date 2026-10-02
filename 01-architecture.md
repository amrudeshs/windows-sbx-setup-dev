# 01 — Recommended Architecture

Back to [README](README.md) · Next: [02-sandboxes-explained.md](02-sandboxes-explained.md)

---

## The recommended system

Install **`sbx` (Docker Sandboxes) on each Windows laptop**. Each developer runs their agent and
their own `docker compose` stack inside a **Linux microVM**. The **shared database** stays on the
**on-prem Linux server** as a normal container, reachable over the LAN.

```
Windows laptops (Windows 11, Intel/AMD)
  ├── Developer A
  │     └── sbx microVM (Linux)
  │           ├── own Docker daemon
  │           ├── own compose stack (app services)
  │           └── own project workspace (mount)
  └── Developer B
        └── sbx microVM (Linux)
              ├── own Docker daemon
              ├── own compose stack (app services)
              └── own project workspace (mount)

                │  network-policy allow: <db-host>:5432
                ▼

On-prem Linux server (Ubuntu 24.04+)
  └── host Docker Engine
        └── shared-postgres container (published on the host)
```

Key properties:

- **Isolation:** hypervisor-level (each sandbox is a microVM with its own kernel, Docker daemon,
  filesystem, and network). No developer touches the host Docker daemon.
- **Independence:** each developer's Compose stack and volumes live in their own sandbox; nothing
  collides.
- **Shared DB:** one Postgres server on the server host, with a **per-developer database and
  role** so no one can wipe another's data.
- **Linux parity:** the sandbox is real Linux, so builds and containers match deployment even
  though the laptops are Windows.

## Why this fits the five requirements

| # | Requirement | How it is met |
| --- | --- | --- |
| 1 | Windows devs + on-prem Linux server | Devs only need a terminal/editor; the Linux work happens in the microVM and on the server. |
| 2 | Common DB container on the Linux box | Postgres runs under the host Docker Engine; sandboxes reach it over LAN via `sbx policy allow network <host>:5432`. |
| 3 | Own `docker compose`, independent | Each sandbox has a private Docker daemon, so Compose runs untouched and isolated. |
| 4 | One engineer can't break the machine | MicroVM boundary: no host FS outside mounts, no host Docker, deny-by-default network. |
| 5 | No WSL2; Linux targets | Sandboxes are Linux microVMs; no WSL2 needed. |

## The alternatives

### Server-hosted `sbx`

Install `sbx` on the server, create one Linux account per developer, and have each developer SSH in
and run `sbx run opencode` in their project directory. Requirements: Ubuntu 24.04+, KVM enabled,
users in the `kvm` group. All elevated work is a one-time action by ops.

Use it when laptops cannot get the one-time admin needed to enable the Windows sandbox runtime, when
you want all compute centralised, or when the Compose stack must literally run on the server.

### Cloud sandboxes (`sbx --cloud`)

Runs on Docker-managed compute. Needs **no local hypervisor and no admin**, but has no host
workspace mounting, is pay-as-you-go, and cannot reach on-prem host paths.

### Comparison

| | `sbx` on laptops | `sbx` on server | Cloud |
| --- | --- | --- | --- |
| Compute | Developer's laptop | Shared server | Docker-managed |
| Compose runs on | Laptop microVM | Server microVM | Cloud |
| Admin needed | One-time (Windows Hypervisor Platform) | One-time (KVM, ops-only) | None |
| Reaches on-prem DB | Over LAN (allow rule) | Best (same host / LAN) | Only via public/tunnelled endpoints |
| Workspace mount | Host mount | Host mount | None (clone inside) |
| Cost | Free (local compute) | Server capacity | Pay-as-you-go |

## The one shared failure domain: the database

Everything else is isolated, so the shared DB is the only cross-user risk. In the recommended
design it lives **outside sandboxes**, on the server's host Docker Engine:

- Give each developer their **own database and role** (not a shared superuser).
- Set **connection limits** and resource caps on Postgres.
- Keep credentials per-developer; prefer `sbx secret set` so values never enter a sandbox.

See [`config/shared-db.compose.yaml`](config/shared-db.compose.yaml) for the server Compose file.

## What to avoid

| Anti-pattern | Why it's wrong |
| --- | --- |
| Everyone sharing one Docker daemon (TCP/SSH context) | No isolation and daemon access is root-equivalent. |
| Mounting the host Docker socket into a container | Containers become host-root. |
| Docker-in-Docker as "isolation" | Requires privileged; partial isolation only. |
| Host users running Compose directly on the server | Fails requirement 4 entirely. |

## Next

- Understand the tool: [02-sandboxes-explained.md](02-sandboxes-explained.md)
- Set up laptops: [07-windows-and-admin.md](07-windows-and-admin.md)
- Put it together: [10-runbook-and-examples.md](10-runbook-and-examples.md)
