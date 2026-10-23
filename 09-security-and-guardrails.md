# 09 — Security and Guardrails

Back to [README](README.md) · Prev: [08-performance.md](08-performance.md) · Next: [10-runbook-and-examples.md](10-runbook-and-examples.md)

This is how requirement 4 ("no single engineer can damage the whole machine") is actually enforced,
and where that protection stops.

---

## Isolation layers

The five isolation layers (hypervisor, network, Docker Engine, workspace, credential) and the list of
things that are always blocked are described once, in
[02-sandboxes-explained.md](02-sandboxes-explained.md#isolation-layers). This document covers what to
add on top and what the isolation does **not** protect against.

## Guardrails to add on top

Applies to the recommended design (sandboxes on laptops, Postgres on the server). Items marked
*server-hosted only* matter only for the [alternative](01-architecture.md#the-alternatives) where
developers have shell accounts on the server.

| Guardrail | Why |
| --- | --- |
| **No developer accounts on the server** | In the recommended design nobody but ops needs a shell on the server. |
| **Never add developers to a host `docker` group** (*server-hosted only*) | Daemon access is root-equivalent on the host and defeats the design. |
| **Host resource limits (systemd slices/cgroups)** (*server-hosted only*) | Stops one sandbox starving the others on a shared server. On laptops use `sandboxOptions.cpus`/`memory`. |
| **Per-developer DB database + role, `PUBLIC` access revoked** | The shared DB is the only shared failure domain. [`db-baseline.sql`](config/db-baseline.sql) and [`provision-developer.sql`](config/provision-developer.sql) implement this. |
| **TLS + SCRAM + source-subnet restriction on Postgres** | Passwords must not cross the LAN in cleartext, and only developer laptops should be able to connect. See [`pg_hba.conf`](config/postgres/pg_hba.conf). |
| **Connection limits, statement/idle timeouts, resource caps on Postgres** | Stop one developer exhausting connections or CPU. |
| **`sandboxOptions.cpus`/`memory` set explicitly** | `cpus: 0` means all host CPUs. |
| **Disk quotas + `sbx prune`** | Sandboxes consume VM + Docker disk (10 GB default each). |
| **`sbx secret set` for model-provider keys** | Keeps those keys out of the sandbox and out of saved templates. Does **not** cover database passwords (see below). |
| **Locked Down network preset + `allowlist.sh`** | One reviewable list of what a sandbox can reach. |
| **Review direct-mounted changes before running modified code** | In direct mode the agent edits your working tree, including Git hooks, Makefiles, `package.json` scripts, CI config. |
| **Database backups** | The shared DB has no isolation to fall back on. See [10 §B](10-runbook-and-examples.md#b-shared-postgres-on-the-linux-server). |

## Secrets

- Store **model-provider keys** with `sbx secret`; the host-side proxy injects them into HTTP request
  headers, so the raw value never enters the VM.
- The GitHub token for `git push` is also a sandbox secret (`sbx secret set github`). Use a
  fine-grained token limited to the project repository: the agent can push whatever it allows
  ([11](11-troubleshooting.md#git-push-fails-with-could-not-read-username)).
- That mechanism is HTTP-only. A **database password cannot be protected this way**: Postgres does
  not use HTTP headers, so the credential has to exist inside the sandbox (an `env:` value or a
  file) and the agent can read it. Plan accordingly:
  - one low-privilege role per developer, not a shared or superuser credential,
  - `sslmode=verify-full` so the password is never sent in cleartext,
  - rotate by re-running `provision-developer.sql` logic (`ALTER ROLE ... PASSWORD`) when a
    developer leaves or a sandbox is shared,
  - never commit a filled-in `sbxenv.yaml`.
- Environment variables set with `-e`/`--env` or `env:` are **readable inside the sandbox** — fine
  for non-secrets, not for model keys.
- Saved templates capture the filesystem; if you manually wrote keys into a sandbox, they end up in
  the template. Prefer managed secrets.

## Prompt injection and exfiltration

Network isolation limits where a compromised agent can talk to; it does not stop a compromised agent.
An agent that reads untrusted content (a dependency's README, an issue, a web page, a hostile repo)
can be steered by instructions hidden in it. Inside the sandbox it has your database credential,
your source code and the Git credentials the proxy injects for allowed hosts.

Realistic abuse paths for this setup:

- **Exfiltrate over an allowed host.** `github.com` is allowed, so the agent can push code or
  secrets to any repository or gist. The same goes for any allowed registry that accepts uploads.
- **Use the DB credential directly** against the developer's own database, or any other database
  that role can connect to (hence `REVOKE CONNECT ... FROM PUBLIC`).
- **Plant code in the mounted workspace** that runs later on the host: Git hooks, build scripts,
  CI config, `.vscode/tasks.json`.

Mitigations, in order of value:

1. **Use [clone mode](03-workspaces.md#clone-mode-read-only-source--private-clone) for untrusted
   code** and for parallel agents, so nothing lands in your working tree until you review and fetch.
2. **Keep the allowlist short** and project-specific (`allowlist.sh` takes the providers you use).
3. **Treat the DB role as exposed** — it should only be able to hurt its owner's database.
4. **Review diffs, including hidden files** (`.git/hooks`, `.vscode`, CI config) before running
   anything the agent changed outside the source tree.
5. **Don't put production credentials in a sandbox.** This setup is for development databases.

## Shared skills caveat

Sandboxes can mount a shared agent-skills store **read-only** by default. If set to `readwrite`, one
sandbox can modify instructions other sandboxes load. `config/sbxenv.yaml` sets `skills: off`; use
`readonly` only if you rely on shared skills.

## MCP caveat

Local stdio MCP servers run **on the host**, not in the sandbox, with host permissions. Treat them as
trusted integrations.

## Governance (optional, paid)

Organization admins can centrally manage network, filesystem, and MCP policies across all local
sandboxes, enforce sign-in, and collect audit logs. When active, only org allow rules grant access
(local allow rules are ignored; local deny rules still apply). This is a separate paid subscription.

## Threat model summary

| Actor | Can affect |
| --- | --- |
| A sandboxed agent behaving normally | Its own VM, its mounted workspace, allowed network destinations. |
| A **steered** agent (prompt injection) | All of the above, plus: anything reachable with the credentials inside the VM (the developer's DB role, injected Git access), data sent out through any allowed host, and files it can plant in a direct-mounted workspace. |
| A developer | Their own sandboxes and their own database (if DB tenancy is enforced). |
| A developer's laptop being compromised | That developer's DB role and anything their sandbox could reach; not other developers' databases. |
| A developer exploiting the sandbox | Host kernel/hypervisor escapes only — a much higher bar than shared-daemon access. |

## Next

- Put it together: [10-runbook-and-examples.md](10-runbook-and-examples.md)
