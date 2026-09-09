# SandboxForge

**Disposable, isolated Docker environments on demand.**

SandboxForge provisions throwaway Docker environments so unproven code can be tested somewhere it can't damage anything that matters.

Testing a script you don't trust usually means running it on your real system and hoping, or hand-rolling a container and cleaning up after it every time. SandboxForge collapses that to one command: create, work, destroy.

Sandboxes are built from a `Dockerfile` at the project root. Edit it to fit whatever needs testing. Reusable profiles and an audit log are planned; see Status.

Third in an operator trilogy alongside [StormForge](https://github.com/StoneyLee63/stormforge). Built phase by phase toward v1.

---

## Status

**Phase 4 of 5. v1 complete.** `create`, `enter`, and `destroy` all work end to end. Phase 5 adds the audit log.

| Phase | Capability | State |
|-------|-----------|-------|
| 0 | Container engine provisioned and verified | Done |
| 1 | CLI skeleton, subcommand dispatch | Done |
| 2 | `create`: build image, start container | Done |
| 3 | `enter`: shell into a running sandbox | Done |
| 4 | `destroy`: clean teardown | Done |
| 5 | Audit log of every lifecycle action | Planned |

Beyond v1: `stop` / `start` to pause a sandbox without destroying it, `list` and `status` for visibility, and additional profiles.

---

## Requirements

- Bash 4+
- Docker Engine, with the invoking user in the `docker` group

Verify the engine before use:

```bash
docker run hello-world
```

---

## Usage

```bash
sandboxforge create <name>   # build image if needed, start a named sandbox
sandboxforge enter <name>              # open a root shell inside it
sandboxforge destroy <name>            # tear it down
```

`destroy` asks for confirmation before removing anything. Leaving a sandbox is just `exit` — that closes the shell and returns you to the host. The sandbox keeps running until you destroy it.

---

## Profiles

**Planned.** Today the tool reads one `Dockerfile` at the project root. Profiles will move that to `profiles/<name>/Dockerfile`, so sandboxing a different kind of work means writing a new profile rather than modifying the tool.

---

## Design notes

`create` builds the image only when it isn't already present locally. Docker's build step contacts the registry to resolve the base image tag, so building unconditionally means `create` hangs or fails with no network. That's exactly what happened offline, on the first real use. Skipping the build when the image already exists means a sandbox can be provisioned with no connectivity at all.

The trade-off: editing the `Dockerfile` won't rebuild an image that already exists. Until a `rebuild` subcommand lands, drop it by hand:

```bash
docker image rm sandboxforge-base:latest
```

Both guard clauses (empty name, name already in use) run before any build or container work. Cheap checks first.

---

## Scope

Containers share the host kernel. Namespaces and cgroups restrict what a process can see and consume, which makes a container an effective **isolation boundary**: it keeps your test environment from colliding with your real system.

It is not a **security boundary**. A kernel-level exploit escapes a container in a way it would not escape a hypervisor. Genuinely hostile code (live malware, adversary tooling) belongs in a virtual machine or a hardened runtime such as gVisor or Kata Containers, not here.

SandboxForge is built for isolating your own unproven work. That's the job it does well, and the line is worth stating plainly.

---

## License

MIT
