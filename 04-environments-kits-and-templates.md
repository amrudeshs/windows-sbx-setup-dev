# 04 — Environments, Kits, and Templates

Back to [README](README.md) · Prev: [03-workspaces.md](03-workspaces.md) · Next: [05-docker-compose-and-shared-db.md](05-docker-compose-and-shared-db.md)

There are four layers you can use to shape what a sandbox contains. Use the lightest one that
does the job.

| Layer | Purpose | Mechanism |
| --- | --- | --- |
| Agent / template | Base OS + agent + tools | `sbx run <agent>` → `docker/sandbox-templates:<variant>` |
| Kits | Package tools, config, network, credentials, agent instructions | `--kit`, kit sets |
| Environment file | Repeatable full environment per project | `sbxenv.yaml` + `sbx env ...` |
| Template image | Snapshot a hand-configured sandbox | `sbx template save` / `-t` |

---

## 1. Pick the agent / template

```sh
sbx run opencode
sbx run claude
sbx run shell          # no agent, manual setup
```

See [02-sandboxes-explained.md](02-sandboxes-explained.md) for the full variant list.

## 2. Kits

A kit packages software and configuration. Two roles:

- **workload** — supplies the base environment and the launch command (passed to `sbx run`/`create`).
- **mixin** — adds tools or behavior to a workload (added with `--kit`).

```sh
sbx run me/my-agent-kit:latest --kit me/my-mixin:latest
```

A **kit set** combines a workload plus mixins into one publishable reference.

Version compatibility:

- **v3 kits** need `sbx` ≥ 0.45.
- Built-in agent names (`opencode`, `claude`, …) are **v2** kits.
- You **cannot mix v2 and v3 kits** in one sandbox.
- To use a v3 mixin, select a v3 workload by its image/path/Git reference.

Kits also declare **network access** and **credentials**, which is handy for standardising which
domains (model providers, private registries) every sandbox may reach.

## 3. Environment files (`sbxenv.yaml`) — the main tool

An environment file captures a sandbox's full setup so the team uses the same agent, tools,
resources, secrets, and ports. `sbx env` is **experimental** — interface may change.

```yaml
schemaVersion: "1"
name: web-app
agent: opencode
workspace: ./web-app
additionalWorkspaces:
  - path: ./shared-components
    readOnly: true
kits:
  - docker.io/sbx/playwright-kit:latest
env:
  NODE_ENV: development
sandboxOptions:
  cpus: 4
  memory: 8g
  skills: off
secrets:
  anthropic:
    command: cat ~/.anthropic-key
ports:
  - sandbox: 3000
    host: 3000
lifecycle:
  postCreate:
    - command: ./scripts/seed-fixtures.sh
      workdir: web-app
```

Commands:

| Command | Description |
| --- | --- |
| `sbx env plan` | Preview changes without applying |
| `sbx env run` | Apply the plan, create if needed, and attach |
| `sbx env create` | Apply the plan without attaching |
| `sbx env exec -- <cmd>` | Run a command in an existing environment |
| `sbx env rm` | Destroy the environment and its resources |

Notes:

- Keep the file **outside** mounted workspaces.
- Put a **per-project** `sbxenv.yaml` in each repo; use **`~/.sbxenv.yaml`** for personal defaults
  (it cannot set `name`).
- **Merge** multiple files; later ones override earlier. Lists concatenate.
- **Parameterize** with an `args:` block and `--env-arg NAME=VALUE` / `--env-args-file`.
- Reference paths with `${{ env.projectDir }}` and `${{ env.fileDir }}`.
- Workspace/kits/ports/secrets/sandboxOptions changes apply only on next **creation** — `sbx env rm`
  then recreate.

A ready-to-use example lives at [`config/sbxenv.yaml`](config/sbxenv.yaml).

### Environment file fields (top level)

`schemaVersion`, `name`, `agent`, `args`, `kits`, `workspace`, `additionalWorkspaces`, `env`,
`sandboxOptions`, `secrets`, `bindings`, `registries`, `mcp`, `ports`, `lifecycle`.

### Resource limits

| Option | Meaning | Default |
| --- | --- | --- |
| `sandboxOptions.cpus` | Number of CPUs (`0` = all host CPUs; `--cpus` on run/create) | `0` |
| `sandboxOptions.memory` | Memory limit (`8g`, `512m`) | host default |
| `sandbox.disk.dockerVolume` | Docker storage inside the sandbox | `10g` |

Per-sandbox disk override: `DOCKER_SANDBOXES_DOCKER_SIZE=30g sbx create ...`.

## 4. Templates (snapshot a configured sandbox)

If you configure a sandbox interactively, save its filesystem as a reusable template:

```sh
sbx template save my-sandbox my-template:v1
sbx run -t my-template:v1 opencode
sbx template ls
sbx template rm my-template:v1
```

Caveats:

- Templates capture the **container filesystem only** — **not** mounted host workspaces and **not**
  `/var/lib/docker` (the sandbox's Docker store).
- Agent user-level config files are recreated on sandbox creation.
- Templates can contain secrets if you stored them in the filesystem — prefer `sbx secret set`,
  which keeps credentials out of the image.

## Choosing a layer

- One-off experiment → **agent/template**.
- Team-wide toolchain + rules → **kit / kit set**.
- Per-project reproducible environment → **`sbxenv.yaml`** (recommended default).
- "I configured it by hand and want to reuse it" → **saved template**.

## Next

- Docker and Compose inside the sandbox: [05-docker-compose-and-shared-db.md](05-docker-compose-and-shared-db.md)
