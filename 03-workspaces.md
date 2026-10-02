# 03 — Workspaces and Naming

Back to [README](README.md) · Prev: [02-sandboxes-explained.md](02-sandboxes-explained.md) · Next: [04-environments-kits-and-templates.md](04-environments-kits-and-templates.md)

A **workspace** is a host directory shared into the sandbox. Host paths appear inside the sandbox
at the **same absolute path**, through a filesystem passthrough, so edits are live in both
directions (no sync step).

---

## Ways to attach a workspace

```sh
# Current directory becomes the primary workspace (read-write)
sbx run opencode

# Explicit path
sbx run opencode ~/my-project

# Mountless sandbox: no host workspace at all
sbx create --name scratch opencode
```

Use `sbx create` instead of `run` to build the sandbox **without attaching** to the agent.

## Multiple workspaces

The **first** path is the primary workspace (agent starts there). Extra paths are mounted too.
Append `:ro` for read-only.

```sh
sbx run opencode ~/project-a ~/shared-libs:ro ~/docs:ro
```

In an environment file (see [`config/sbxenv.yaml`](config/sbxenv.yaml)):

```yaml
workspace: ./web-app
additionalWorkspaces:
  - path: ./shared-components              # read-write
  - path: ./architecture-docs
    readOnly: true
```

Use `additionalWorkspaces` for related repos, shared libraries, or docs the agent must consult.

## Clone mode (read-only source + private clone)

```sh
sbx run --clone opencode ~/my-project
```

- Host repo is mounted **read-only** at `/run/sandbox/source`.
- The agent works in a **private in-VM clone**; host working tree is untouched.
- Changes stay in the sandbox until fetched/pushed.
- Clone mode is fixed at creation time and requires the primary workspace to be a Git repository.

Use clone mode when running several agents on one repo, or when you don't want the agent editing
your working tree directly.

## How sandboxes are identified: folder vs name

Both matter, and this is a common source of confusion:

- **Sandboxes are named.** `--name` gives an explicit identity. Once named, reattach from anywhere:
  ```sh
  sbx run --name my-sandbox
  ```
- **Without a name, the workspace path is the key.** "Running the same workspace path again
  reconnects to the existing sandbox rather than creating another."
- **Multiple sandboxes on one folder:** give each a distinct name.
  ```sh
  sbx run opencode --name feature ~/my-project
  sbx run opencode --name spike   ~/my-project
  ```
- **Environment files** default the name to `<agent>-<workspace-basename>`, overridable via the
  `name:` field or `--name`.

So a sandbox is **not rigidly tied to a folder** — you can name it independently and reopen it from
anywhere — but absent a name, identity is derived from the mounted workspace.

## Best practices

- **Mount source, not build output.** Keep generated directories with heavy I/O (`node_modules`,
  `.venv`, `target/`, `dist/`) **off** the bind mount — put them on the sandbox disk (mountless or
  named Docker volumes). This is the single biggest performance win. See
  [08-performance.md](08-performance.md).
- **Never mount network/SMB/NFS/cloud-synced folders** as a workspace — every file op crosses the
  network and agent performance collapses.
- **Keep `sbxenv.yaml` outside mounted workspaces** (it is mounted read-only into the sandbox; if it
  is inside a writable mount, the agent could alter it).
- **One sandbox per project** for a clean environment; use `--name` only for parallel work on the
  same repo.

## Next

- Shaping each environment: [04-environments-kits-and-templates.md](04-environments-kits-and-templates.md)
