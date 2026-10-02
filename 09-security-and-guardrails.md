# 09 — Security and Guardrails

Back to [README](README.md) · Prev: [08-performance.md](08-performance.md) · Next: [10-runbook-and-examples.md](10-runbook-and-examples.md)

This is how requirement 4 ("no single engineer can damage the whole machine") is actually enforced.

---

## Isolation layers (from Docker's model)

1. **Hypervisor isolation** — separate kernel per sandbox; no shared memory or processes with the host.
2. **Network isolation** — outbound TCP proxied through the host, deny-by-default; UDP off; ICMP blocked.
3. **Docker Engine isolation** — each sandbox has its own engine; no path to the host daemon.
4. **Workspace isolation** — mountless / clone / direct mount, your choice.
5. **Credential isolation** — API keys injected into HTTP headers by the host proxy; raw values never
   enter the VM.

### Blocked by default (not changeable by policy)

- Host filesystem access outside mounted workspaces and the shared skills store.
- The host Docker daemon.
- Direct sandbox-to-sandbox network communication.
- Direct external ICMP.

## Guardrails to add on top

| Guardrail | Why |
| --- | --- |
| **Never add developers to the host `docker` group** | Daemon access = root-equivalent on the host and defeats the whole design. Only ops needs host Docker. |
| **Per-developer DB database + role** | The shared DB is the only shared failure domain; prevent cross-developer database damage. |
| **Connection limits + resource caps on Postgres** | Stop one dev exhausting connections/CPU. |
| **Host resource limits (systemd slices/cgroups)** and `sandboxOptions.cpus`/`memory` | Prevent one sandbox starving others. |
| **Disk quotas + `sbx prune`** | Sandboxes consume VM + Docker disk (10 GB default each). |
| **`sbx secret set` for credentials** | Keeps raw values out of the sandbox and out of saved templates. |
| **Standard network rules in a kit** | Consistent, auditable egress across the team. |
| **Review direct-mounted changes before running modified code** | In direct mode the agent edits your working tree, including Git hooks, Makefiles, `package.json` scripts, CI config. |

## Secrets

- Store provider keys with `sbx secret`; the host-side proxy injects them at request time.
- Environment variables set with `-e`/`--env` are **readable inside the sandbox** — fine for
  non-secrets, not for keys.
- Saved templates capture the filesystem; if you manually wrote keys into a sandbox, they end up in
  the template. Prefer managed secrets.

## Shared skills caveat

Sandboxes can mount a shared agent-skills store **read-only** by default. If set to `readwrite`, one
sandbox can modify instructions other sandboxes load. Use `--skills=off` or `skills: off` when this
risk isn't acceptable.

## MCP caveat

Local stdio MCP servers run **on the host**, not in the sandbox, with host permissions. Treat them as
trusted integrations.

## Governance (optional, paid)

Organization admins can centrally manage network, filesystem, and MCP policies across all local
sandboxes, enforce sign-in, and collect audit logs. When active, only org allow rules grant access
(local allow rules are ignored; local deny rules still apply).

## Threat model summary

| Actor | Can affect |
| --- | --- |
| A sandboxed agent | Its own VM, its mounted workspace, allowed network destinations. |
| A developer | Their own sandboxes and DB schema (if DB tenancy is enforced). |
| A developer exploiting the sandbox | Host kernel/hypervisor escapes only — a much higher bar than shared-daemon access. |

## Next

- Put it together: [10-runbook-and-examples.md](10-runbook-and-examples.md)
