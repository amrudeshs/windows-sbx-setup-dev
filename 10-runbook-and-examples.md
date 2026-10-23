# 10 — Runbook and Examples

Back to [README](README.md) · Prev: [09-security-and-guardrails.md](09-security-and-guardrails.md) · Next: [11-troubleshooting.md](11-troubleshooting.md)

Copy-paste material for rolling this out. The ready-to-use files are in [`config/`](config/). Verify
`sbx` flags against your installed version with `sbx <cmd> --help`. The quick-start steps (laptop
setup, per-project environment, network policy) are in the [README](README.md#how-to-use-it) and
are not repeated here.

---

## A. Developer laptop onboarding checklist (Windows 11)

- [ ] IT: enable `HypervisorPlatform` once per machine (elevated, reboot) —
  [07](07-windows-and-admin.md).
- [ ] Developer: install `sbx` per-user:
  ```powershell
  winget install -h Docker.sbx
  ```
- [ ] `sbx login` (see the Docker account question in [07](07-windows-and-admin.md#sign-in)).
- [ ] First run: choose the **Locked Down** network preset.
- [ ] Store the model-provider credential:
  ```sh
  sbx secret set anthropic      # or openai / openrouter / google / xai
  ```
- [ ] Receive the DB credential and CA certificate from ops (never over chat or email in clear).
- [ ] Clone the project onto the laptop.
- [ ] Apply the network policy, then test the DB path ([11](11-troubleshooting.md)):
  ```sh
  sh config/allowlist.sh 10.0.0.5 anthropic
  sbx run opencode
  ```

## B. Shared Postgres on the Linux server

Ops-managed, on the **host Docker Engine** — never inside a sandbox (sandboxes cannot reach each
other).

### One-time server prerequisites

1. **TLS certificate** for the server name or IP developers connect to, with a CA developers can
   trust. For a quick internal setup:
   ```sh
   mkdir -p config/certs && cd config/certs
   openssl req -new -x509 -days 825 -nodes -subj "/CN=<db-host>" \
     -addext "subjectAltName=IP:<db-host>" -keyout server.key -out server.crt
   sudo chown 999:999 server.key server.crt && sudo chmod 600 server.key
   ```
   Distribute `server.crt` (or your CA's root) to developers as `shared-db-ca.crt`. With a
   self-signed certificate, that file *is* the CA. Plan renewal before expiry.
2. **`config/postgres/pg_hba.conf`**: set the CIDR to the developer subnet.
3. **Host firewall**: allow 5432 only from that subnet (Docker publishes ports ahead of `ufw`
   INPUT rules, so also keep `DB_BIND_ADDR` on the LAN IP rather than `0.0.0.0`).

### Start it

```sh
cd config
export POSTGRES_PASSWORD=<strong-secret>   # ops only
export DB_BIND_ADDR=<server-lan-ip>
docker compose -f shared-db.compose.yaml up -d
docker compose -f shared-db.compose.yaml ps        # wait for "healthy"
docker exec -i shared-postgres psql -U postgres -v ON_ERROR_STOP=1 < db-baseline.sql   # once
```

### Provision a developer

```sh
PW="$(openssl rand -base64 24)"
docker exec -i shared-postgres psql -U postgres -v ON_ERROR_STOP=1 \
  -v dev=alice -v pw="$PW" < provision-developer.sql
echo "$PW"      # hand to the developer once, through a password manager
```

The developer's connection string is
`postgres://alice:<pw>@<db-host>:5432/alice_app?sslmode=verify-full&sslrootcert=<path-to-ca>`.
Rotate: `ALTER ROLE alice PASSWORD '<new>';`.

### Offboard a developer

```sh
docker exec shared-postgres pg_dump -U postgres -Fc alice_app > alice_app.dump   # if needed
docker exec -i shared-postgres psql -U postgres -v ON_ERROR_STOP=1 \
  -v dev=alice < deprovision-developer.sql
```

### Back up

The shared DB is the one shared failure domain, so back it up and test the restore:

```sh
# nightly, from cron on the server
docker exec shared-postgres pg_dumpall -U postgres | gzip > /backups/shared-pg-$(date +%F).sql.gz

# restore test (into a scratch container, not production)
gunzip -c /backups/shared-pg-<date>.sql.gz | docker exec -i <scratch-container> psql -U postgres
```

Keep backups off the same disk, apply retention, and restrict who can read them (they contain every
developer's data and password hashes).

## C. Per project

Environment file and day-to-day commands: [README step 3](README.md#3-per-project-copy-the-environment-file).
Config details: [04](04-environments-kits-and-templates.md).

## D. Common commands cheat sheet

```sh
# Lifecycle
sbx run opencode ~/my-project          # create + attach
sbx run --name feature opencode ~/proj # named sandbox
sbx run --name feature                 # reattach by name
sbx run --clone opencode ~/my-project  # private clone; host tree untouched
sbx create --name scratch opencode     # create without attaching
sbx ls                                 # list sandboxes
sbx stop my-sandbox
sbx rm my-sandbox
sbx prune --dry-run

# Shell inside a sandbox
sbx exec -it my-sandbox bash

# Ports
sbx ports my-sandbox --publish 8080:3000
sbx ports my-sandbox

# Files
sbx cp ./config.json my-sandbox:/home/agent/workspace/
sbx cp my-sandbox:/home/agent/workspace/out.log ./

# Environments
sbx env plan | run | create | exec | rm

# Templates
sbx template save my-sandbox my-template:v1
sbx run -t my-template:v1 opencode

# Policy and settings
sbx policy ls
sbx settings list
sbx settings set sandbox.disk.dockerVolume 30g
sbx daemon restart
```

## E. Server-hosted `sbx` (alternative, not recommended here)

Use only if laptops cannot get the one-time admin action ([01](01-architecture.md#the-alternatives)).
Developers then need accounts on the server, so the *server-hosted only* guardrails in
[09](09-security-and-guardrails.md#guardrails-to-add-on-top) apply.

Server setup (ops, once):

```sh
# Ubuntu 24.04+
lsmod | grep kvm                       # confirm KVM
curl -fsSL https://get.docker.com -o get-docker.sh   # review it first
sudo SBX=1 sh get-docker.sh
sudo usermod -aG kvm alice             # per developer
```

Developer (over SSH):

```sh
ssh alice@dev-server
sbx login
cd ~/src/my-project
sbx policy allow network localhost:5432   # DB is on this same host
sbx run opencode
```

Editing: VS Code **Remote-SSH** to the server on the project directory (the same directory the
sandbox mounts read-write); run the agent in a terminal. This workflow applies **only** to this
alternative — in the recommended design files live on the laptop.

## F. Cleanup / disk

```sh
sbx stop my-sandbox
sbx rm my-sandbox
sbx prune --dry-run
sbx prune
sbx template ls && sbx template rm <name>
```

---

## Appendix: local model servers (Ollama)

If a developer runs a model server **on the same machine as `sbx`** (e.g. Ollama on the laptop), that
machine *is* the sandbox host, so `host.docker.internal` is correct. The proxy translates it to
`localhost`, so Ollama can stay on its default loopback address:

```sh
ollama serve                                   # default: listens on 127.0.0.1 only
sbx policy allow network localhost:11434
```

Do **not** set `OLLAMA_HOST=0.0.0.0`: that exposes an unauthenticated model server to the whole
network, and the sandbox does not need it. If a sandbox cannot reach a loopback-only server on your
`sbx` version, bind to the specific interface it needs and firewall it instead.

[`config/opencode.json`](config/opencode.json) points OpenCode at the host model. The two models
listed are **examples**; replace them with whatever your team has tested for agentic coding (very
small reasoning models such as `deepseek-r1:1.5b` are poor at it).

This is the **local-host** case only. For the team's **shared DB on the server**, remember it is
remote — allow `<server>:5432`, not `host.docker.internal`.

---

## Reference links

- <https://docs.docker.com/ai/sandboxes/>
- <https://docs.docker.com/ai/sandboxes/install/>
- <https://docs.docker.com/ai/sandboxes/usage/>
- <https://docs.docker.com/ai/sandboxes/architecture/>
- <https://docs.docker.com/ai/sandboxes/security/>
- <https://docs.docker.com/ai/sandboxes/configuration/>
- <https://docs.docker.com/ai/sandboxes/customize/>
- <https://docs.docker.com/ai/sandboxes/integrations/>
- <https://docs.docker.com/reference/cli/sbx/>
