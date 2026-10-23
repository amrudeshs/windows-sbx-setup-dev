# 08 — Performance: How Fast Is It?

Back to [README](README.md) · Prev: [07-windows-and-admin.md](07-windows-and-admin.md) · Next: [09-security-and-guardrails.md](09-security-and-guardrails.md)

## Verdict

There **is** real overhead, so it is not identical to native development. CPU-bound work should be
close to native because it runs under hardware virtualization; host-mounted file I/O is where it
differs. **This repo contains no measurements**, so treat the statements below as expectations to
verify with the benchmark at the end, not as results. Docker's docs:

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
| Native Linux dev | Expected: slower on host-mounted file I/O, close on CPU/builds. Smallest gap on a Linux host (native KVM). |
| WSL2 | Same class of virtualization; `sbx` adds a second boundary (VM + its own daemon), so expect somewhat more overhead for much stronger isolation. |
| Docker Desktop | Expected to be in the same range for Linux containers, with stronger isolation. Unmeasured here. |

## Laptop sizing

Each sandbox reserves `sandboxOptions.memory` (8g in the example) plus its Docker volume (10 GB
disk by default). Budget: **sum of sandbox memory + about 4 GB for Windows and the editor must fit in
laptop RAM**, so a 16 GB laptop fits one 8g sandbox comfortably and two only with smaller limits.
Set `cpus` explicitly too; `0` means all host CPUs.

## Rollout advice

Benchmark one representative project on one laptop. Record these three timings in each environment,
run three times each, and compare medians:

| Step | Native (your current setup) | Inside the sandbox, source on the host mount | Inside the sandbox, deps on the sandbox disk |
| --- | --- | --- | --- |
| Dependency install (`npm ci`, `pip install -r ...`) | | | |
| Full build | | | |
| Test suite | | | |

Run the sandbox commands from `sbx exec -it <sandbox> bash`, with `time` in front. The third column
is the "generated dirs on the sandbox disk" pattern from above. Discard the first run in each new
sandbox (cold caches). If column three is not acceptably close to your baseline, raise it
before rollout.

## Next

- Keeping the machine safe: [09-security-and-guardrails.md](09-security-and-guardrails.md)
