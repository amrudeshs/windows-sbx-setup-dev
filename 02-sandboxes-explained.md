# 02 — Docker Sandboxes Explained

Back to [README](README.md) · Prev: [01-architecture.md](01-architecture.md) · Next: [03-workspaces.md](03-workspaces.md)

`sbx` is Docker's CLI for running AI coding agents in **isolated microVMs**. It runs on macOS,
Windows 11, and Ubuntu 24.04+ Linux.

---

## What a sandbox is

Each sandbox is a **microVM** — not a container — with:

- its **own kernel** (hypervisor isolation),
- its **own Docker Engine** (no path to the host daemon),
- its **own filesystem** (installed packages, images, volumes),
- its **own network** (deny-by-default egress through a host-side proxy).

Inside the VM the agent has **full control**: `sudo`, package installs, a private Docker daemon,
and read/write access to its filesystem plus any mounted workspace.

## Isolation layers

1. **Hypervisor isolation** — separate kernel per sandbox; no shared memory or processes with the host.
2. **Network isolation** — outbound TCP is proxied through the host and governed by a
   deny-by-default policy; UDP is off unless enabled; ICMP is blocked.
3. **Docker Engine isolation** — each sandbox has its own engine; the host daemon is unreachable.
4. **Workspace isolation** — mountless, clone mode, or direct mount (your choice).
5. **Credential isolation** — API keys are injected into HTTP headers by the host-side proxy; raw
   values never enter the VM.

### Blocked by default (not configurable)

- Host filesystem access outside explicitly mounted workspaces and the shared skills store.
- The host Docker daemon.
- Direct network communication **between sandboxes**.
- Direct external ICMP.

## Default Linux images (templates)

Docker's sandbox templates are published as **`docker/sandbox-templates:<variant>`**. They are
**Ubuntu-based**, run as a non-root `agent` user (UID 1000, home `/home/agent`) with `sudo`, and
most include Git, the Docker CLI, and common toolchains (Node, Python, Go, Java).

| Variant | Agent |
| --- | --- |
| `claude-code` | Claude Code |
| `claude-code-minimal` | Claude Code, minimal toolset (no Node/Python/Go/Java) |
| `codex` | OpenAI Codex |
| `copilot` | GitHub Copilot CLI |
| `cursor-agent` | Cursor |
| `devin` | Devin CLI |
| `docker-agent` | Docker Agent |
| `droid` | Droid |
| `gemini` | Gemini CLI |
| `kiro` | Kiro |
| `opencode` | OpenCode |
| `shell` | No agent — for manual setup |

Docker Hardened variants are `dhi/sbx-templates:<variant>` when `platform.images.useDHI` is on.

### Bring your own Linux image

You can start from any Linux image if it meets the contract:

- `curl`, `git`, trusted CA certificates.
- Executable `/bin/sh` and `/bin/bash`.
- A non-root `agent` account, UID 1000, home `/home/agent`, listed in `/etc/passwd`, with `USER agent`.
- `ENTRYPOINT`/`CMD` set to the agent or shell to launch.

## Lifecycle and persistence

- `sbx run` boots the microVM and attaches you to the agent.
- Everything inside — packages, images, containers, volumes, mountless workspace files — **persists
  across stop/start**.
- `sbx rm` deletes the sandbox and all of its contents.
- A **directly mounted workspace lives on the host** and is not deleted with the sandbox.

## Comparison to alternatives

| Approach | Isolation | Docker access | Use case |
| --- | --- | --- | --- |
| **Sandboxes (microVMs)** | Full (hypervisor) | Isolated daemon | Autonomous agents |
| Container with socket mount | Partial (namespaces) | Shared host daemon | Trusted tools |
| Docker-in-Docker | Partial (privileged) | Nested daemon | CI/CD |
| Host execution | None | Host daemon | Manual development |

Sandboxes trade **higher resource overhead (a VM plus its own daemon)** for complete isolation.

## Cost / licensing

- The **`sbx` CLI and local sandbox compute are free to use, including commercially**.
- **Cloud sandbox compute** is pay-as-you-go.
- **Organization governance** (central network/filesystem/MCP policy, audit logs, sign-in
  enforcement) is a separate paid tier.

## Next

- Working with files: [03-workspaces.md](03-workspaces.md)
- Shaping environments: [04-environments-kits-and-templates.md](04-environments-kits-and-templates.md)
