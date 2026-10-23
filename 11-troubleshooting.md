# 11 — Troubleshooting

Back to [README](README.md) · Prev: [10-runbook-and-examples.md](10-runbook-and-examples.md)

Start with the symptom. Commands assume the recommended design (sandbox on a laptop, Postgres on the
server).

---

## A request is blocked (HTTP 403)

Blocked HTTP/HTTPS requests return **403**; read the response body, which says why. The four cases:

| Body says | Meaning | Action |
| --- | --- | --- |
| `Approval required for <host>` | A pending approval exists for this request. | Ask the laptop's owner to review it on the host: `sbx policy approval ls`, then `sbx policy approval inspect <id>` and `sbx policy approval respond <id> --option <option-id>`. |
| `Blocked by local rule for <host>` | A local **deny** rule matches. Deny beats allow. | `sbx policy ls` to find it; remove it with `sbx policy rm network --resource <host>` (or `--sandbox <name>` for a per-sandbox rule). |
| `Blocked by org policy` | Central governance blocks it. | Don't add local allows; contact IT. |
| `Blocked by network policy: domain <host> ... no matching allow rule` | Default deny. | Add the host to `config/allowlist.sh` (after `--`) or run `sbx policy allow network <host>:443`. |

Inspect recent attempts with `sbx policy log` and active rules with `sbx policy ls`.

## The database is unreachable

Work from the laptop outward; each step rules out one layer.

1. **Is the rule there?** `sbx policy ls` should list `<db-host>:5432`. If not, re-run
   `sh config/allowlist.sh <db-host> <providers>`.
2. **Is the port reachable from inside the sandbox?**
   ```sh
   sbx exec -it <sandbox> bash
   # inside the sandbox:
   timeout 5 bash -c '</dev/tcp/<db-host>/5432' && echo "port open" || echo "blocked/unreachable"
   ```
   - `port open` → the network path works; go to step 4.
   - Fails → step 3.
3. **Is it the laptop/LAN, or the sandbox?** From a Windows shell on the same laptop, test the
   server directly: `Test-NetConnection <db-host> -Port 5432`. If that fails too, it is routing, VPN
   or the server firewall — not `sbx`. If it succeeds but the sandbox check fails, check
   `sbx policy log` for the block reason. If the host's IP stack is the problem (connections hang or
   fail rather than being blocked), ask the host admin about the proxy's IP-stack setting
   (`DOCKER_SANDBOXES_IP_STACK`).
   - If the policy allows it and the laptop can reach it but the sandbox cannot, the proxy may not
     forward raw (non-HTTP) TCP on your `sbx` version. That is the main assumption of this design
     ([05](05-docker-compose-and-shared-db.md#reaching-the-shared-db--the-important-part)). Fall
     back to the server-hosted alternative ([01](01-architecture.md#the-alternatives)) and report
     it upstream.
4. **Does the server accept you?** Failures here come from Postgres, not the network:
   - `no pg_hba.conf entry for host ...` → the laptop's address is outside the CIDR in
     `config/postgres/pg_hba.conf`, or the connection is not using TLS. Remember the server sees the
     **laptop's** address, not the sandbox's.
   - `SSL error` / `certificate verify failed` → the `sslrootcert` file is missing in the sandbox or
     does not match the server certificate/name (`verify-full` checks the host name or IP).
   - `password authentication failed` → wrong password or role; ops can rotate with
     `ALTER ROLE <dev> PASSWORD '...'`.
   - `permission denied for database` → the database was not provisioned for that role.
   - `too many connections for role` → hit `CONNECTION LIMIT 20`; find leaks, or raise per role.
5. **Server side:** `docker logs shared-postgres` shows connection attempts (connections and
   disconnections are logged).

## `host.docker.internal` does not reach the database

By design: it points at the **laptop**. Use `<db-host>:5432`.

## Sandbox disk is full

Multi-service Compose stacks fill the 10 GB default Docker volume.

```sh
docker system df            # inside the sandbox
docker system prune         # inside the sandbox; removes stopped containers and dangling images
sbx prune --dry-run         # on the host: removes unused sandboxes
sbx settings set sandbox.disk.dockerVolume 30g   # applies to newly created sandboxes
```

## Everything is slow

1. Are `node_modules`/`.venv`/build output on the host mount? Move them to the sandbox disk
   ([08](08-performance.md)).
2. Is the workspace on a network or cloud-synced folder? Move it to a local disk.
3. Is total sandbox memory/CPU above what the laptop has? See *Laptop sizing* in [08](08-performance.md).

## `sbx env` complains about unknown fields or version

- v3 kits need `sbx` ≥ 0.45, and v2/v3 kits cannot be mixed ([04](04-environments-kits-and-templates.md)).
- `sbx env` is experimental: check `sbx --version` and `sbx env --help` against the field list in
  [04](04-environments-kits-and-templates.md). Environment changes apply only after
  `sbx env rm` and recreation.
- Pin one `sbx` version for the team and upgrade deliberately; re-check this repo's docs against
  [docs.docker.com/ai/sandboxes](https://docs.docker.com/ai/sandboxes/) when you do.

## Published ports are not reachable from Windows

The service must listen on `0.0.0.0` inside the sandbox (not `127.0.0.1`) and the port must be
published with `sbx ports <sandbox> --publish HOST:SANDBOX`. `sbx run` on an existing sandbox
ignores `--publish`.
