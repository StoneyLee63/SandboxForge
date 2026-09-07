# SandboxForge

**Disposable, isolated Docker environments on demand.**

SandboxForge provisions throwaway Docker environments so unproven code can be tested somewhere it can't damage anything that matters.

Testing a script you don't trust usually means running it on your real system and hoping, or hand-rolling a container and cleaning up after it every time. SandboxForge collapses that to one command: create, work, destroy.

Sandboxes are built from profiles — reusable environment definitions you modify to fit whatever needs testing. Every action writes a timestamped entry to an audit log.

Third in an operator trilogy alongside [StormForge](https://github.com/StoneyLee63/stormforge). Built phase by phase toward v1.

---

## Status

**Phase 1 of 5.** The CLI routes its subcommands; container operations are next.

| Phase | Capability | State |
|-------|-----------|-------|
| 0 | Container engine provisioned and verified | Done |
| 1 | CLI skeleton, subcommand dispatch | Done |
| 2 | `create` — build image, start container | In progress |
| 3 | `enter` — shell into a running sandbox | Planned |
| 4 | `destroy` — clean teardown | Planned |
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
sandboxforge create <profile> [name]   # provision a sandbox from a profile
sandboxforge enter <name>              # open a shell inside it
sandboxforge destroy <name>            # tear it down
```

Leaving a sandbox is just `exit` — that closes the shell and returns you to the host. The sandbox keeps running until you destroy it.

---

## Profiles

A profile is a directory under `profiles/` containing a `Dockerfile` that defines one kind of environment. Profiles are the extension point: to sandbox a different kind of work, write a new profile rather than modifying the tool.

---

## Scope

Containers share the host kernel. Namespaces and cgroups restrict what a process can see and consume, which makes a container an effective **isolation boundary** — it keeps your test environment from colliding with your real system.

It is not a **security boundary**. A kernel-level exploit escapes a container in a way it would not escape a hypervisor. Genuinely hostile code — live malware, adversary tooling — belongs in a virtual machine or a hardened runtime such as gVisor or Kata Containers, not here.

SandboxForge is built for isolating your own unproven work. That's the job it does well, and the line is worth stating plainly.

---

## License

MIT
