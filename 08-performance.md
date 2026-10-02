# 08 — Performance: How Fast Is It?

Back to [README](README.md) · Prev: [07-windows-and-admin.md](07-windows-and-admin.md) · Next: [09-security-and-guardrails.md](09-security-and-guardrails.md)

## Verdict

There **is** real overhead, so it is not identical to native development — but for typical
coding/agent workloads it is usually close enough that you won't notice. Docker's docs:

> Sandboxes trade **higher resource overhead (a VM plus its own daemon)** for complete isolation.

---

## Where it's near-native (fast)

- **CPU-bound work** — compiles, tests, package installs, `docker build`. Hardware virtualization
  (KVM / Windows Hypervisor Platform / Apple Virtualization) runs near-native.
- **Docker inside the sandbox** — runs on the VM's local disk; comparable to Docker Desktop, often
  better for Linux containers.
- **Startup after first run** — cached image + persistent VM → seconds. (First run pulls the image
  and boots the VM, so it is slower.)

## Where you'll feel the slowdown

- **File I/O on the host-mounted workspace.** Direct mounts go through a **filesystem passthrough
  (virtiofs)**; every read/write crosses the VM boundary. Virtiofs caching (on by default) hides much
  of this for read-heavy work, but heavy small-file writes (`npm install` into a bind-mounted
  `node_modules`, large artifact writes back to the host) are slower.
- **Network-attached / synced storage is a hard no.** Network drives, SMB/NFS shares, cloud-synced
  folders mounted as a workspace make every file op cross the network — "slows agent performance
  dramatically."
- **Added network latency.** All outbound TCP is proxied through the host.
- **Disk footprint.** Each sandbox has its own VM image + Docker store (default 10 GB), unshared
  between sandboxes; the first build in each sandbox is cold.
- **Resource contention.** `cpus: 0` defaults to **all** host CPUs; several such sandboxes will
  compete and slow the host.

## How to keep it close to native

1. **Keep generated/IO-heavy dirs off the bind mount.** Put `node_modules`, `.venv`, `target/`,
   `dist/`, and Docker volumes on the **sandbox disk** (mountless or named volumes). Mount only
   source. *Biggest win.*
2. **Mount source, not giant monorepo trees.**
3. **Don't disable virtiofs caching** (on by default; opt-out is
   `DOCKER_SANDBOXES_ENABLE_VIRTIOFS_CACHE=0`).
4. **Set explicit limits** — `sandboxOptions.cpus` / `memory` — and don't over-allocate across
   sandboxes.
5. **Use clone mode or mountless** for I/O-heavy or parallel-agent work.
6. **Never mount SMB/NFS/cloud-synced folders.**
7. **Right-size disk** (`sandbox.disk.dockerVolume`) so builds aren't fighting for space.

## Compared to alternatives

| Compared with | Result |
| --- | --- |
| Native Linux dev | Slightly slower on host-mounted file I/O; near-identical on CPU/builds. Smallest gap on a Linux host (native KVM). |
| WSL2 | Same class of virtualization; `sbx` adds a second boundary (VM + its own daemon), a bit heavier but far more isolated. |
| Docker Desktop | Usually similar or better for Linux containers, and much better isolated. |

## Rollout advice

Benchmark one representative project on one laptop — run `npm ci`, a full build, and the test suite
both natively and inside a sandbox. That tells you more than any general figure. Then apply the
"generated dirs on the sandbox disk" pattern and re-measure.

## Next

- Keeping the machine safe: [09-security-and-guardrails.md](09-security-and-guardrails.md)
