# 07 — Windows Setup and Admin Requirements

Back to [README](README.md) · Prev: [06-networking-and-policy.md](06-networking-and-policy.md) · Next: [08-performance.md](08-performance.md)

## Prerequisites (local sandboxes on Windows)

- **Windows 11**
- **64-bit Intel or AMD processor** (Windows ARM is not listed for local sandboxes)
- **Windows Hypervisor Platform** enabled

## Does it need admin? — precise answer

**No WSL2. But yes, a one-time elevated action.**

| Step | Admin? |
| --- | --- |
| Install `sbx` per-user (`winget install -h Docker.sbx`) | **No** — installs to `%LOCALAPPDATA%`, no elevation |
| Install all-users (`DockerSandboxesMachine.msi`) | Yes (elevated) — prefer the per-user install |
| Enable **Windows Hypervisor Platform** (required for local sandboxes) | **Yes, one-time, elevated**, plus likely a reboot |
| Enable CPU virtualization in BIOS/UEFI (if off) | Physical/BIOS access |
| Day-to-day `sbx run` | **No admin** |

The docs instruct, for Windows:

> To run local sandboxes, open an **elevated PowerShell prompt** and turn on Windows Hypervisor
> Platform:
> ```powershell
> Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
> ```

So "no WSL2" is correct, but "no admin at all" is **not** — the microVM runtime needs the Windows
Hypervisor Platform feature.

### The ask for IT (word it carefully)

- We are **not** asking for WSL2.
- We are asking to enable the **Windows Hypervisor Platform** optional feature (not the Hyper-V
  management role) and hardware virtualization in firmware.

Have IT enable it **once per laptop** (manually, or via Intune/MDM/GPO). After that, developers
install `sbx` per-user and use it without admin.

### Intune / MDM snippet

```powershell
# One-time, elevated, per machine
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart

# Then, as the developer (no admin):
winget install -h Docker.sbx
```

> If laptops are **Windows 11 Home**, verify Windows Hypervisor Platform availability on that
> edition before committing — the docs only specify "Windows 11".

## If zero admin is non-negotiable

Local sandboxes are not possible. Options:

1. **Cloud sandboxes** — `sbx --cloud` needs no local hypervisor and no admin, but has no host
   workspace mount and is pay-as-you-go.
2. **`sbx` on the Linux server** — keep all elevated work on the server, done once by ops via KVM.
   See [10-runbook-and-examples.md](10-runbook-and-examples.md).

## Linux server prerequisites (for server-hosted `sbx`, or for the shared DB host)

- **Ubuntu 24.04+**, 64-bit Intel/AMD or Arm.
- **KVM** available and enabled; user in the `kvm` group:
  ```sh
  lsmod | grep kvm
  sudo usermod -aG kvm $USER
  newgrp kvm
  ```
- Nested virtualization if the server is itself a VM.

### Install `sbx`

```sh
# macOS
brew trust docker/tap && brew install docker/tap/sbx

# Windows (per-user, no admin)
winget install -h Docker.sbx

# Linux — Engine + sbx together
curl -fsSL https://get.docker.com | sudo SBX=1 sh

# Linux — sbx only (no host Engine)
curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh
sudo apt install docker-sbx
```

### Sign in

```sh
sbx login
```

Requires a Docker account (each developer uses their own). On headless Linux there is no desktop
keyring, so secrets fall back to a `0700` file under `~/.config/com.docker.sandboxes`; the CLI prints
a notice.

## First-run network preset

On first run, choose a default network policy — pick **Balanced** (deny by default, common dev sites
allowed). Adjust later with `sbx policy`.

## Next

- Speed expectations: [08-performance.md](08-performance.md)
