# 06 — Networking and Policy

Back to [README](README.md) · Prev: [05-docker-compose-and-shared-db.md](05-docker-compose-and-shared-db.md) · Next: [07-windows-and-admin.md](07-windows-and-admin.md)

## Deny by default

A fresh sandbox blocks **all outbound TCP** (HTTP, HTTPS, SSH) unless an explicit rule allows the
destination. UDP is off unless enabled; ICMP is blocked; DNS enforces policy. You allow destinations
with `sbx policy`.

```sh
sbx policy ls                          # show active rules
sbx policy allow network registry.npmjs.org
sbx policy allow network api.anthropic.com
sbx policy allow network github.com:443
sbx policy allow network 10.0.0.5:5432   # the on-prem shared DB
sbx policy deny  network example.com
sbx policy rm    network example.com
```

On first run, `sbx` asks you to pick a **global preset**:

| Preset | Behaviour |
| --- | --- |
| Open | All traffic allowed |
| **Balanced** | Default deny, common dev sites allowed (recommended start) |
| Locked Down | Everything blocked until explicitly allowed |

## Host services from a sandbox

Services on the **host that runs `sbx`** are reachable via `host.docker.internal`. The proxy
translates it to `localhost`, so allow the port first:

```sh
sbx policy allow network localhost:11434
# then: curl http://host.docker.internal:11434
```

> **Critical for the team design:** on a **laptop** sandbox, `host.docker.internal` = the **laptop**.
> The shared DB is on the **server**. Reach it with the server's host/IP and an allow rule
> (`sbx policy allow network <server>:5432`). Only use `host.docker.internal` for services running
> on the same machine as `sbx`.

## What is always blocked

- Host filesystem outside mounted workspaces and the shared skills store.
- The host Docker daemon.
- **Direct network communication between sandboxes** (a feature, for your model).
- Direct external ICMP.

## Recommended allow list for this team

| Purpose | Rule |
| --- | --- |
| Model provider | `sbx policy allow network <provider-domain>` (e.g. `api.anthropic.com`, `api.x.ai`, `opencode.ai`) |
| Package registries | `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`, `proxy.golang.org`, `crates.io`, … |
| Source control | `github.com:443`, your Git host |
| Shared DB | `sbx policy allow network <db-host>:5432` |
| Local model (if used) | `sbx policy allow network localhost:11434` |

A ready-to-run script lives at [`config/allowlist.sh`](config/allowlist.sh):

```sh
sh config/allowlist.sh 10.0.0.5
```

Bake standard rules into a **kit** to give the whole team the same egress automatically
(see [04-environments-kits-and-templates.md](04-environments-kits-and-templates.md)).

## Governance (optional)

Organization admins can centrally manage network, filesystem, and MCP policies across all local
sandboxes, plus sign-in enforcement and audit logs. This is a **separate paid subscription**.
When org governance is active, only org allow rules grant access; local allow rules are ignored
(local deny rules still apply).

## Upstream / corporate proxies

`sbx` can chain through an upstream proxy (HTTP/HTTPS/SOCKS5, PAC, or the OS proxy) and has separate
settings for sandbox vs daemon traffic:

```sh
sbx settings set proxy http://proxy.corp:3128
sbx settings set no_proxy "registry.internal,10.0.0.0/8"
sbx daemon restart
```

Proxy exclusions do **not** grant network access — policy still applies.

## Next

- Windows prerequisites and admin: [07-windows-and-admin.md](07-windows-and-admin.md)
