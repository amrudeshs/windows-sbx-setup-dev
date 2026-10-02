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

Then point the Compose app at `10.0.0.5:5432` (or a DNS name the sandbox proxy can resolve).

Outbound TCP from containers inside the sandbox egresses through the sandbox proxy, so the allow
rule is what makes it work. **Test this path early** — it is the only cross-boundary connection in
the design.

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
- **Connection limits** and resource caps on Postgres.
- Per-developer credentials; prefer `sbx secret set` so values never enter a sandbox.

Sample Compose for the shared DB: [`config/shared-db.compose.yaml`](config/shared-db.compose.yaml).
Per-developer setup SQL: [10-runbook-and-examples.md](10-runbook-and-examples.md).

## Next

- Network policy in depth: [06-networking-and-policy.md](06-networking-and-policy.md)
