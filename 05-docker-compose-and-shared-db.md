# 05 — Docker Compose and the Shared DB

Back to [README](README.md) · Prev: [04-environments-kits-and-templates.md](04-environments-kits-and-templates.md) · Next: [06-networking-and-policy.md](06-networking-and-policy.md)

## Yes — Compose runs fully inside the sandbox

Each sandbox has **its own private Docker daemon**. Agents (and developers) can build images, run
containers, and use Compose. Docker's docs:

> Everything runs inside the sandbox's private Docker daemon, so containers started by the agent
> never appear in your host's `docker ps`.

Consequences:

- Two developers running the same Compose project **never collide** on ports, image names, or volumes.
- Images, containers, and volumes persist across stop/start and are deleted only on `sbx rm`.
- **Build caches are per sandbox** — the first build in a new sandbox is cold.

## Verified: Docker inside a sandbox

Tested on 2026-10-23 inside a real `sbx` sandbox (Ubuntu 26.04 microVM, **linux/arm64**, kernel
7.0.14, Docker Engine 29.9.2, Compose v5.6.1, `overlayfs` storage driver, cgroup v2, runc). The
developer laptops in this design are x86-64, so **re-run the test there** with
[`scripts/dind-smoke-test.sh`](scripts/dind-smoke-test.sh) (`sh scripts/dind-smoke-test.sh` from a
shell inside the sandbox; it cleans up after itself and exits non-zero on any failure).

| # | Check | Result |
| --- | --- | --- |
| 1 | The daemon is the sandbox's own: `docker info` reports the sandbox's name, `0` containers and `0` images at the start, and a container reports the sandbox VM's kernel | Pass |
| 2 | Run a container from a locally built image (`docker import` of a static busybox, no registry needed). It had its own PID 1, hostname and process list | Pass |
| 3 | `docker pull hello-world` from Docker Hub | **Failed**: `x509: certificate signed by unknown authority` (corporate TLS inspection, see below) |
| 4 | Fetch the same Hub image with `skopeo`, trusting the corporate CA for that command only, load it into the daemon, `docker run hello-world` | Pass (exit 0) |
| 5 | Two containers on a user-defined network resolve each other by name | Pass |
| 6 | A two-service Compose project (one service pings the other by service name) via `docker compose up --exit-code-from` | Pass |

What this shows: containers, user-defined networks, name resolution and Compose all work in the
sandbox's private daemon, which is what the design relies on.

What it does **not** show:

- **Pulling images needs the corporate root CA trusted inside the sandbox** when the network does
  TLS inspection (row 3). Until that is solved, `docker compose up` in a fresh sandbox fails at the
  pull step. See [11-troubleshooting.md](11-troubleshooting.md#docker-pull-fails-with-x509-certificate-signed-by-unknown-authority).
- That the containers are invisible to the *host's* `docker ps`: the host side was not inspected.
  The isolation claim comes from Docker's docs plus checks 1 and 2.
- The shared-DB path ([11](11-troubleshooting.md#the-database-is-unreachable)), x86-64 behaviour,
  performance, or large stacks hitting the 10 GB Docker volume.

## Disk

All Docker data lives in the sandbox's Docker volume, **10 GB by default**. Multi-service stacks
fill it fast.

```sh
# One-off
DOCKER_SANDBOXES_DOCKER_SIZE=30g sbx create opencode ~/my-project

# Persistent default
sbx settings set sandbox.disk.dockerVolume 30g
```

## Reaching services from Windows

Sandbox services are not reachable from the host by default. Publish the port and make the service
listen on `0.0.0.0` (not just `127.0.0.1`).

```sh
# At creation
sbx run --publish 8080:3000 opencode ~/my-project

# On an existing sandbox
sbx ports my-sandbox --publish 8080:3000
sbx ports my-sandbox            # list mappings
sbx ports my-sandbox --unpublish 8080:3000
```

Then open `http://localhost:8080` on Windows. `sbx ls` shows active mappings. When `sbx run`
reattaches to an existing sandbox it **ignores `--publish`** — use `sbx ports`.

## Reaching the shared DB — the important part

The shared Postgres runs on the **on-prem Linux server**, not on the laptop. That means:

- **Do not use `host.docker.internal`** to reach it. Inside a laptop sandbox, `host.docker.internal`
  maps to the **laptop**, not the server.
- Use the server's **hostname or IP + port**, and allow it in the network policy:

```sh
sbx policy allow network 10.0.0.5:5432
```

Then point the Compose app at `10.0.0.5:5432` (or a DNS name the sandbox proxy can resolve) with
`sslmode=verify-full`, as in [`config/sbxenv.yaml`](config/sbxenv.yaml).

Outbound TCP from containers inside the sandbox egresses through the sandbox proxy, so the allow
rule is what makes it work. **Test this path early** — it is the only cross-boundary connection in
the design. Whether the proxy forwards raw (non-HTTP) TCP such as the Postgres protocol is assumed
here, not demonstrated; the test in [11-troubleshooting.md](11-troubleshooting.md#the-database-is-unreachable)
settles it for your `sbx` version. If it fails, the fallback is the server-hosted alternative in
[01](01-architecture.md#the-alternatives).

### Local model servers (e.g. Ollama on the laptop)

If a developer runs a model server **on their own laptop**, that *is* the sandbox host, so
`host.docker.internal` is correct:

```sh
sbx policy allow network localhost:11434
# then use http://host.docker.internal:11434
```

See `config/opencode.json` and the appendix in [10-runbook-and-examples.md](10-runbook-and-examples.md).

## Recommended Compose pattern

Keep heavy/generated directories on the sandbox disk, mount only source:

- Put `node_modules`, `.venv`, build output in **named Docker volumes** or inside the sandbox's
  filesystem — not on the host-mounted workspace.
- Bind-mount only the source tree for live editing.

This keeps the slow filesystem-passthrough path limited to source files.

## DB tenancy (do this)

The DB is the only shared component, so protect it:

- **One database + role per developer** on the shared Postgres; no shared superuser.
  [`provision-developer.sql`](config/provision-developer.sql) does this and revokes `PUBLIC` access.
- **Connection limits**, statement/idle timeouts and resource caps on Postgres.
- **TLS + SCRAM + subnet restriction** ([`pg_hba.conf`](config/postgres/pg_hba.conf)).
- Per-developer credentials. `sbx secret` cannot hold a Postgres password (it only injects HTTP
  headers), so the password is visible inside the sandbox; the isolated, low-privilege role is
  what limits the damage ([09](09-security-and-guardrails.md#secrets)).

Sample Compose for the shared DB: [`config/shared-db.compose.yaml`](config/shared-db.compose.yaml).
Per-developer setup SQL: [10-runbook-and-examples.md](10-runbook-and-examples.md).

## Next

- Network policy in depth: [06-networking-and-policy.md](06-networking-and-policy.md)
