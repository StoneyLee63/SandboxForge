# Phase 0 — Container Engine Provisioning on WSL Ubuntu

*SandboxForge build log — Phase 0 of 5*

---

## Objective

Install and verify Docker Engine from Docker's official repository on WSL Ubuntu, establishing the container runtime that SandboxForge depends on.

**Skills practiced:** APT repository trust and package management, GPG key handling, systemd service control, Linux group membership, client/daemon architecture.

**Why it matters:** A tool that provisions containers is worthless if the engine underneath it isn't installed correctly, running persistently, and usable without privilege escalation on every call. Phase 0 exists so that every later phase can assume a working, verified foundation instead of debugging one.

---

## Environment

- **Distribution:** Ubuntu 24.04.4 LTS (Noble Numbat)
- **Platform:** WSL2 on Windows
- **User Context:** Standard user with sudo privileges
- **Init System:** systemd (confirmed as PID 1)

---

## Scenario

A new build project requires Docker as its runtime engine, but the host has no container runtime installed. The engine must be installed from the vendor's own repository rather than the distribution's default packages (which lag behind and lack the plugin components), the repository must be cryptographically verified before any package is trusted, the daemon must survive reboots, and the working user must be able to invoke it without `sudo` on every command.

This is standard onboarding work for any Linux host that will run containerized workloads.

---

## Technical Concepts Covered

- APT package management and repository configuration
- GPG repository signing and the `signed-by` trust model
- The `sudo` + shell redirection problem, and `tee` as the resolution
- Init system identification via PID 1
- systemd service management — the `start` vs `enable` distinction
- Linux supplementary group membership and login-time group resolution
- Client/daemon architecture (`docker` vs `dockerd`, `systemctl` vs `systemd`)
- Container isolation primitives — namespaces and cgroups

---

## Commands Used

```bash
# Identify the target release
cat /etc/os-release

# Refresh package index and install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# Create the keyring directory and fetch Docker's signing key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
ls -l /etc/apt/keyrings/docker.asc

# Register Docker's repository, scoped to the verified key
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install the engine, CLI, runtime, and plugins
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Identify the init system before attempting service control
ps -p 1 -o comm=

# Start the daemon now, and enable it at boot
sudo systemctl start docker
sudo systemctl enable docker
sudo systemctl status docker --no-pager

# Grant the working user daemon access without sudo
sudo usermod -aG docker $USER

# Verify (in a new shell, so group membership is re-evaluated)
id
docker run hello-world
```

---

## Procedure

1. **Identified the target release.** Read `/etc/os-release` to confirm the distribution codename (`noble`) before configuring any repository, since Docker's repository paths are versioned by codename.

2. **Installed prerequisites.** Confirmed `ca-certificates` and `curl` were present — the first provides the trust chain for verifying HTTPS connections to Docker's servers, the second retrieves the signing key.

3. **Established repository trust.** Created `/etc/apt/keyrings/` with `0755` permissions, downloaded Docker's GPG public key into it, and set the key world-readable so APT can read it during unprivileged read operations. Verified the key file landed with non-zero size before proceeding.

4. **Registered the repository.** Wrote a single source line to `/etc/apt/sources.list.d/docker.list` binding the repository to the architecture (`dpkg --print-architecture`), the codename (read dynamically from `/etc/os-release`), and — critically — the specific key file via `signed-by=`. Re-ran `apt-get update` to confirm APT could fetch and verify the new repository's metadata.

5. **Installed the engine.** Pulled `docker-ce` (daemon), `docker-ce-cli` (client), `containerd.io` (low-level runtime), and the buildx and compose plugins.

6. **Identified the init system.** Checked PID 1 before attempting service control, to determine whether `systemctl` or `service` was the correct management interface.

7. **Started and enabled the daemon.** Started `docker.service` for the current session and enabled it for subsequent boots, then confirmed state via `systemctl status`.

8. **Granted user-level daemon access.** Added the working user to the `docker` group with `usermod -aG`, preserving existing group memberships.

9. **Verified in a fresh shell.** Opened a new terminal (required — group membership is resolved at login), confirmed group assignment with `id`, and ran `docker run hello-world` to prove end-to-end function.

---

## Results

**What worked:**

- Docker's repository registered and verified cleanly — `apt-get update` fetched `noble InRelease [48.5 kB]` and `noble/stable amd64 Packages [65.2 kB]` from `download.docker.com` with no signature warnings, confirming the key and `signed-by` binding were correct.
- Docker Engine `5:29.8.0-1~ubuntu.24.04~noble` and `containerd.io 2.3.4-2` installed successfully, with systemd unit symlinks created for `docker.service`, `docker.socket`, and `containerd.service`.
- `systemctl status docker` returned `Active: active (running)` with `Main PID: 4083 (dockerd)` and `enabled` on the Loaded line.
- `id` confirmed group `989(docker)` added while `27(sudo)` was retained.
- `docker run hello-world` pulled the image and ran the container with no `sudo`.

**What didn't (and what it taught):**

- **`E: Unable to locate package ca-certificate`** — the package name was typed singular. APT matches package names as exact strings with no fuzzy matching, so a missing character reads identically to a nonexistent package. First diagnostic step for this error is always spelling, before assuming the package is unavailable.
- **`curl: option -o: requires parameter`** — the command line was submitted with the `-o` flag but no output path following it. `-o` designates where curl writes its output instead of printing to stdout; without an argument it has no destination and refuses rather than guessing. Flags that take values fail immediately when separated from them.

---

## Evidence

Repository verification during `apt-get update`:

```
Get:4 https://download.docker.com/linux/ubuntu noble InRelease [48.5 kB]
Get:6 https://download.docker.com/linux/ubuntu noble/stable amd64 Packages [65.2 kB]
Fetched 114 kB in 2s (71.8 kB/s)
```

Daemon state:

```
● docker.service - Docker Application Container Engine
     Loaded: loaded (/usr/lib/systemd/system/docker.service; enabled; preset: enabled)
     Active: active (running) since Sun 2026-09-06 13:58:54 CDT
   Main PID: 4083 (dockerd)
      Tasks: 14
     Memory: 25.0M (peak: 30.5M)
```

Group membership after `usermod`:

```
uid=1000(ltksol) gid=1000(ltksol) groups=1000(ltksol),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),100(users),989(docker)
```

Final verification:

```
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

---

## Key Takeaways

- **`start` and `enable` are independent operations.** `start` runs a service now; `enable` creates the symlink that brings it up at boot. A service that "works until reboot" was started but never enabled. Both are required for persistence.

- **`sudo` elevates the command, not the shell's redirection.** `sudo echo "x" > /etc/protected-file` fails because the `>` is handled by the unprivileged parent shell before `sudo` ever executes. `tee` solves this because `tee` itself is the process running with elevated privilege.

- **Group membership is resolved at login, not on demand.** An open shell keeps the group set it started with. Adding a user to a group requires a new session before it takes effect — this is why the `docker` group appears to "not work" immediately after `usermod`.

- **`usermod -G` without `-a` replaces supplementary groups rather than appending.** Omitting `-a` while adding a user to `docker` strips them from `sudo` and every other supplementary group. On a single-admin host this is a self-inflicted lockout.

- **PID 1 identifies the service management interface.** Checking what owns PID 1 before running `systemctl` avoids misdiagnosing "systemd not running" errors as service failures.

- **Client and daemon are separate programs.** `docker` is a client that sends API requests to `dockerd`; `systemctl` is a client that sends requests to `systemd`. "Cannot connect to the Docker daemon" is not a broken CLI — it is a CLI with nothing listening on the other end.

---

## What This Demonstrates

- **Repository trust is explicit and scoped.** The `signed-by=` directive binds a repository to one specific key, so a compromise of one vendor's key cannot authorize packages from another repository. This replaced the deprecated global `apt-key` model, where any trusted key could vouch for any source.

- **systemd separates runtime state from boot configuration.** These are two distinct properties of a unit, queryable independently, and confirmed together in the `Loaded:` and `Active:` lines of `systemctl status`.

- **Container isolation is a kernel feature, not an emulation layer.** Containers use namespaces (restricting what a process can see — its own PID tree, mount view, network stack) and cgroups (restricting what it can consume — CPU, memory). The container shares the host kernel rather than booting its own, which is why startup is measured in milliseconds instead of the tens of seconds a virtual machine requires.

---

## Security / Administration Relevance

**Supply chain verification.** Installing from a vendor repository without pinning the signing key means trusting whatever the network returns. The keyring-plus-`signed-by` pattern is the practical control against repository substitution and package tampering, and it is the same reasoning that underpins package signing requirements in hardened build environments.

**The `docker` group is root-equivalent privilege.** A member of the `docker` group can start a container mounting the host root filesystem and read or write anything on it — without a password prompt and without a `sudo` log entry. It is not a lesser privilege than `sudo`; it is a quieter one. On shared or production hosts this is an audit finding, and rootless Docker or explicitly brokered access is the correct control. Acceptable on a single-user development host, but the reasoning should be deliberate rather than incidental.

**Containers are an isolation boundary, not a security boundary.** Because containers share the host kernel, a kernel-level exploit escapes the container. Workloads involving genuinely untrusted code — malware analysis, adversary tooling — belong in virtual machines or hardened runtimes such as gVisor or Kata Containers. Knowing where that boundary sits determines whether a sandbox design is appropriate to its threat model.

**Service persistence is a detection surface.** The `start` versus `enable` distinction cuts both ways: an attacker establishing persistence enables a unit so it survives reboot. Auditing which units are enabled — not merely which are running — is a standard persistence-hunting technique.

---

## Time Spent

~60 minutes

---

## Conclusion

Validated a complete container runtime installation on WSL Ubuntu 24.04 from Docker's official repository, with cryptographic verification of the package source, persistent daemon configuration under systemd, and non-privileged user access confirmed by a successful `hello-world` run.

This establishes the engine layer that SandboxForge is built on. Phase 1 begins the tool itself — the CLI skeleton and subcommand dispatch that `create`, `enter`, and `destroy` will hang from.

---

## Glossary

**APT** — Debian and Ubuntu's package management system. Resolves dependencies, verifies signatures, and installs software from configured repositories.

**Architecture** — the CPU instruction set a binary is compiled for (`amd64`, `arm64`). Reported by `dpkg --print-architecture`.

**cgroups (control groups)** — the kernel feature limiting what resources a process may consume: CPU, memory, I/O.

**Codename** — the release name of an Ubuntu version (`noble` for 24.04). Repository paths are organized by codename.

**Container** — a process running on the host kernel with a restricted view of the system, isolated by namespaces and constrained by cgroups.

**Daemon** — a background process with no controlling terminal, running continuously to serve requests. Conventionally named with a trailing `d` (`dockerd`, `sshd`, `systemd`), though the convention is not universal.

**`dpkg`** — the low-level Debian package tool. APT sits on top of it.

**GPG key** — a cryptographic key used to sign and verify packages, proving they originated from the stated publisher and were not modified in transit.

**Hypervisor** — the layer that runs virtual machines, each with its own kernel. A stronger isolation boundary than a container, at higher resource cost.

**Image** — a read-only filesystem template from which containers are created. One image can produce many containers.

**Init system** — the first process the kernel starts (PID 1), responsible for starting and supervising all other services. `systemd` on modern Linux.

**Keyring** — a store of trusted signing keys. Modern APT uses `/etc/apt/keyrings/` with per-repository scoping rather than one global trust store.

**Namespaces** — the kernel feature restricting what a process can see: its own process tree, filesystem view, network stack, and hostname.

**Package** — a bundled unit of software with metadata and dependency information, distributed as a `.deb` file on Debian-based systems.

**PID 1** — the first process started by the kernel and the ancestor of every other process. Identifiable with `ps -p 1 -o comm=`.

**Repository** — a server hosting packages and the metadata describing them, configured in `/etc/apt/sources.list.d/`.

**Service** — a unit of software managed by the init system, typically a daemon.

**`signed-by`** — an APT source directive binding one repository to one specific signing key, so a key trusted for one source cannot vouch for another.

**`start` vs `enable`** — `start` runs a service now, for this boot only. `enable` configures it to start automatically at boot. They are independent; persistence requires both.

**`sudo`** — runs a single command with elevated privileges. It elevates the command only — shell redirection is handled by the unprivileged parent shell before `sudo` executes.

**Symlink (symbolic link)** — a file that points to another path. systemd uses symlinks to record which units are enabled.

**`systemctl`** — the client program used to send requests to systemd. It is the interface, not the service manager itself.

**`systemd`** — the init system and service manager on modern Linux distributions. Runs as PID 1.

**Supplementary group** — a group a user belongs to beyond their primary group. Resolved at login, so changes require a new session to take effect.

**`tee`** — reads standard input and writes it to both a file and standard output. Used with `sudo` to write to protected paths, since the elevated process performs the write directly.

**`usermod -aG`** — modifies a user account. `-G` sets supplementary groups; `-a` appends rather than replaces. Omitting `-a` removes the user from every group not listed.
