# 10 — Runbook and Examples

Back to [README](README.md) · Prev: [09-security-and-guardrails.md](09-security-and-guardrails.md)

Copy-paste material for rolling this out. The ready-to-use files are in [`config/`](config/). Verify
`sbx` flags against your installed version with `sbx <cmd> --help`.

---

## A. Developer laptop onboarding checklist (Windows 11)

- [ ] IT: enable `HypervisorPlatform` once per machine (elevated, reboot).
- [ ] Developer: install `sbx` per-user:
  ```powershell
  winget install -h Docker.sbx
  ```
- [ ] `sbx login` (Docker account; each developer uses their own).
- [ ] First run: choose the **Balanced** network preset.
- [ ] Store the model-provider credential:
  ```sh
  sbx secret set anthropic      # or openai / openrouter / google / xai
  ```
- [ ] Clone the project onto the laptop.
- [ ] Apply the network policy and run the agent:
  ```sh
  sh config/allowlist.sh 10.0.0.5
  sbx run opencode
  ```

## B. Shared Postgres on the Linux server

[`config/shared-db.compose.yaml`](config/shared-db.compose.yaml):

```sh
cd config
POSTGRES_PASSWORD=<strong-secret> docker compose -f shared-db.compose.yaml up -d
```

> Keep this container on the **host Docker Engine**, managed by ops. Do not put it in a sandbox —
> sandboxes cannot reach each other.

### Per-developer database and role

Run once per developer against the shared Postgres:

```sql
CREATE ROLE alice LOGIN PASSWORD 'alice-strong-password'
  CONNECTION LIMIT 20;
CREATE DATABASE alice_app OWNER alice;
```

Each developer points their app at `alice_app` on `<db-host>:5432` and never gets superuser.

## C. Per project: use the environment file

Copy [`config/sbxenv.yaml`](config/sbxenv.yaml) into a folder **beside** the project (not inside a
mounted workspace), edit the name, DB URL, and ports, then:

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

## D. Policy rules (network)

```sh
sh config/allowlist.sh 10.0.0.5
sbx policy ls
```

## E. Common commands cheat sheet

```sh
# Lifecycle
sbx run opencode ~/my-project          # create + attach
sbx run --name feature opencode ~/proj # named sandbox
sbx run --name feature                 # reattach by name
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

# Settings
sbx settings list
sbx settings set sandbox.disk.dockerVolume 30g
sbx daemon restart
```

## F. Server-hosted `sbx` (alternative)

Server setup (ops, once):

```sh
# Ubuntu 24.04+
lsmod | grep kvm                       # confirm KVM
sudo curl -fsSL https://get.docker.com | sudo SBX=1 sh
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
sandbox mounts read-write), and run the agent in a terminal. Direct mount means edits are live.

## G. Cleanup / disk

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
machine *is* the sandbox host, so `host.docker.internal` is correct.

On the host:

```sh
OLLAMA_HOST=0.0.0.0 ollama serve
```

Allow the port:

```sh
sbx policy allow network localhost:11434
```

OpenCode config — see [`config/opencode.json`](config/opencode.json) — points at the host model:

```sh
sbx run opencode
```

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
