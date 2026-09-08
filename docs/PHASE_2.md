# Phase 2 — Image Build and Container Provisioning

*SandboxForge build log — Phase 2 of 5*

---

## Objective

Replace the `create` stub with real container provisioning: build a Docker image from a definition in the repository, start a named container from it, and refuse invalid input before any of that work begins.

**Skills practiced:** Dockerfile authoring, Docker image and container lifecycle, script self-location with `BASH_SOURCE`, guard clause construction, using command exit status as a conditional test, file descriptor redirection, Docker CLI output formatting with Go templates, execution timing with `time`.

**Why it matters:** Phase 1 proved the routing. This phase proves the first real operation the tool performs, and it is the operation every later phase depends on — `enter` and `destroy` are meaningless without a container that reliably exists and can be found by name. It is also where the tool stops being a script that runs on one machine in one directory and becomes something that runs anywhere.

---

## Environment

- **Distribution:** Ubuntu 24.04.4 LTS (Noble Numbat)
- **Platform:** WSL2 on Windows
- **Container engine:** Docker Engine, installed and verified in Phase 0
- **User Context:** Standard user, member of the `docker` group
- **Editors:** nano and VS Code
- **Repository:** `~/projects/flagships/sandboxforge`

---

## Scenario

A tool that provisions disposable environments is only worth using if provisioning is dependable. Two failure modes decide that.

The first is location. A CLI installed on `PATH` gets invoked from wherever the operator happens to be standing. If the tool resolves its own files relative to the working directory, it works during development — where you are always in the project folder — and breaks the first time someone actually uses it.

The second is the network. Building a container image normally reaches a registry. A sandbox tool whose pitch is "spin one up anywhere" and which then requires connectivity to do so is not the tool it claims to be.

Both were addressed in this phase, and the second was found the hard way.

---

## Technical Concepts Covered

- Dockerfile instruction syntax as a build language distinct from Bash
- `FROM` and base image selection
- `CMD` and the container's main process
- Container lifetime tied to PID 1
- Image tags as mutable pointers versus immutable image IDs
- Content-addressable storage and SHA256 layer digests
- Build context and default Dockerfile resolution
- Layer caching and cached build steps
- Detached containers (`-d`) and named containers (`--name`)
- Script self-location with `BASH_SOURCE` and `dirname`
- Nested command substitution
- Parent directory traversal (`..`) inside constructed paths
- Guard clauses and fail-fast ordering
- String emptiness testing with `[[ -z ]]`
- Any command's exit status as an `if` condition
- Logical negation with `!`
- File descriptor redirection: `>/dev/null 2>&1`
- Docker CLI `--format` Go templates
- Exact whole-line matching with `grep -qx`
- `return` versus `exit` inside a function
- Wall-clock versus CPU time with `time`

---

## Commands Used

```bash
# Create the image definition at the project root
cd ~/projects/flagships/sandboxforge
nano Dockerfile

# Build the image by hand before scripting it
docker build -t sandboxforge-base:latest .

# Provision and verify
./bin/sandboxforge.sh create testbox
docker ps

# Prove the tool works outside the project directory
cd ~
~/projects/flagships/sandboxforge/bin/sandboxforge.sh create roambox
docker ps

# Exercise the guard clauses
./bin/sandboxforge.sh create
./bin/sandboxforge.sh create testbox

# Measure execution to distinguish network stalls from real work
time ./bin/sandboxforge.sh create testbox2
time ./bin/sandboxforge.sh create planebox

# Commit the checkpoint
git add -A
git status
git commit -m "Phase 2: create builds image and starts named sandbox"
git push
```

---

## Procedure

1. **Wrote the image definition.** Created `Dockerfile` at the project root — deliberately beside `bin/`, not inside it, so the build context is the repository itself. Two instructions: `FROM ubuntu:24.04` to establish the base filesystem, and `CMD ["sleep", "infinity"]` to define the container's main process.

2. **Chose `sleep infinity` over `/bin/bash` for `CMD`.** A container lives exactly as long as its main process. `bash` with no terminal attached finds nothing to do and exits immediately, killing the container within the same second it started. `enter` in Phase 3 attaches to an already-running container, so the container must stay up after `create` returns. A process that never finishes is what keeps it there.

3. **Built the image manually before scripting it.** Ran `docker build -t sandboxforge-base:latest .` directly to confirm the Dockerfile was valid in isolation — the same separation-of-failure-domains discipline used in Phase 1. Verified the tag in the build output (`naming to docker.io/library/sandboxforge-base:latest`) rather than assuming.

4. **Built `create_sandbox()` incrementally.** Defined the function above `main()` so it exists before `main "$@"` invokes it at the bottom of the file. Added `local name="$1"` — the function's own first positional parameter, independent of the script's — then `local image="sandboxforge-base:latest"`, matching the tag used in the manual build.

5. **Made the script locate itself.** `script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` resolves the directory holding the script file, steps up one level to the repository root, and stores the absolute path. This replaces the working directory as the anchor for the build context, which is what makes the tool location-independent.

6. **Added the build and run calls.** `docker build -t "$image" "$script_dir"` — no `-f` needed, since Docker looks for a file named `Dockerfile` inside the given context directory. Then `docker run -d --name "$name" "$image"`: detached so the script does not block behind `sleep infinity`, and named so `enter` and `destroy` have a stable handle instead of a generated container ID.

7. **Wired the function into the dispatch table**, replacing the `create` stub with `create_sandbox "${1:-}"`. The `${1:-}` default is required because `main()` already consumed the subcommand with `shift`, and `set -u` would abort on a missing sandbox name.

8. **Verified provisioning**, then verified portability separately by running the tool from the home directory with an absolute path. Both containers appeared in `docker ps` with status `Up`, running `sleep infinity`.

9. **Added two guard clauses at the top of the function** — one rejecting an empty name, one rejecting a name already in use — placed above the build so that no expensive work runs before cheap validation.

10. **Reversed the build strategy on evidence** after an offline failure (below), wrapping the build in `if ! docker image inspect "$image" >/dev/null 2>&1`.

11. **Reconciled the README with the implementation** after finding it documented a profile system that does not exist, then committed the checkpoint.

---

## Results

**What worked:**

- `create <name>` builds the image when absent, starts a detached container under that name, and returns in under a second when the image already exists.
- The tool provisions correctly from any working directory, verified from `~` with no Dockerfile present there.
- Both guard clauses reject bad input with a message on stderr and a non-zero return, without building anything.
- With the image already present, `create` completes with no build output and no network access at all.

**What didn't (and what it taught):**

**Bug 1 — mistyped subcommand read as a bad flag.** `docker buid -t sandboxforge-base:latest .` failed with `unknown shorthand flag: 't' in -t`. The error names the flag, but the flag was fine. Docker's CLI reads the word after `docker` as the subcommand and hands the remainder to that subcommand's parser. `buid` matched no subcommand, so `-t` was never routed to `build`'s parser and fell through to the base command, which has no `-t`.

The generalization: **when a CLI rejects a flag you know is valid, suspect the command word in front of it.** The parser that would have understood the flag was never reached.

**Bug 2 — the tool failed with no network, which changed a design decision.** A `create` invocation hung for 44 seconds on `load metadata for docker.io/library/ubuntu:24.04` and had to be cancelled. That step is BuildKit contacting the registry to resolve the base image tag to a digest. It runs on every build, cached layers or not.

The original design called `docker build` unconditionally on the reasoning that layer caching made rebuilds nearly free — measured at 2.0 seconds against 17 seconds cold. That reasoning was sound about CPU cost and silent about connectivity. The machine was offline, and offline is precisely the condition a portable sandbox tool is supposed to survive.

The fix was to build only when the image is absent locally:

```bash
if ! docker image inspect "$image" >/dev/null 2>&1; then
    docker build -t "$image" "$script_dir"
fi
```

`docker image inspect` queries the local image store and never touches the network. Provisioning time dropped from 2.043s to 0.588s, and the network dependency disappeared from the common path entirely.

The accepted trade-off is recorded in the README: editing the `Dockerfile` no longer rebuilds an existing image. Until a `rebuild` subcommand exists, `docker image rm sandboxforge-base:latest` forces it.

**Bug 3 — a guard clause that failed open.** The duplicate-name check was written as `docker ps -a --format '{{.Name}}'`. Docker's container context exposes `Names`, plural; there is no `Name` field. The template engine errored with `can't evaluate field Name in type *formatter.ContainerContext`.

The important part is what happened next. The failing `docker ps` produced no output, `grep` therefore found no match and returned non-zero, the `if` read that as "no duplicate exists," and execution continued straight into the build and the container start — which then failed with Docker's own `Conflict` error. The guard did not block anything and did not announce that it had broken.

**A guard built on a command that can itself fail does not fail closed. It fails open, silently, admitting exactly what it was written to stop.** Correcting `.Name` to `.Names` produced the intended refusal.

**Bug 4 — documentation describing unbuilt features.** The README documented `create <profile> [name]`, a `profiles/` directory, and an audit log. None exist. A reader cloning the repository would have run the documented command and gotten a container named after a nonexistent profile. Corrected by documenting the built state and demoting the profile system to a labelled `Planned` section rather than deleting the idea.

---

## Evidence

Provisioning and verification:

```
$ ./bin/sandboxforge.sh create testbox
[+] Building 2.2s (5/5) FINISHED
 => CACHED [1/1] FROM docker.io/library/ubuntu:24.04@sha256:33ceb71981b602c1a7443
 => => naming to docker.io/library/sandboxforge-base:latest
8c46e69ae0137fb84405973b8f4fe9c9b0e971a738414c8f3eba27882c3428d2

$ docker ps
CONTAINER ID   IMAGE                      COMMAND            STATUS         NAMES
8c46e69ae013   sandboxforge-base:latest   "sleep infinity"   Up 13 seconds  testbox
```

Location independence, run from the home directory:

```
$ cd ~
$ ~/projects/flagships/sandboxforge/bin/sandboxforge.sh create roambox
[+] Building 2.2s (5/5) FINISHED
2becb16f9067b50e4ece447f0444d3812c81725e9011f576c2bdfc56bb4f45d0

$ docker ps
CONTAINER ID   IMAGE                      COMMAND            STATUS          NAMES
2becb16f9067   sandboxforge-base:latest   "sleep infinity"   Up 3 seconds    roambox
8c46e69ae013   6f658846e7d2               "sleep infinity"    Up 8 minutes    testbox
```

Note `testbox` displaying a raw image ID rather than a tag. The second build produced a new image and `:latest` moved to point at it, leaving the running container's original image untagged. Tags are pointers; image IDs are identity.

Guard clauses:

```
$ ./bin/sandboxforge.sh create
sandboxforge: create requires a sandbox name

$ ./bin/sandboxforge.sh create testbox
sandboxforge: sandbox 'testbox' already exists
```

Offline failure, before the fix:

```
$ ./bin/sandboxforge.sh create testbox
[+] Building 44.1s (2/2) FINISHED
 => CANCELED [internal] load metadata for docker.io/library/ubuntu:24.04    44.0s
ERROR: failed to build: failed to solve: Canceled: context canceled
```

Provisioning after the fix, with the image already present:

```
$ time ./bin/sandboxforge.sh create planebox
0771afeddaa40b9a5ada130f7a6b9f4ef6dd8d0ea120529043fbba0155a7edb6

real    0m0.588s
user    0m0.049s
sys     0m0.087s
```

No build output, no registry contact.

---

## Key Takeaways

- **Cheap checks first, expensive work last.** Both guards run before any build or container operation. Ordered the other way, a duplicate name costs a full build before Docker refuses — work done purely to discover it should not have started.

- **A guard whose test command can fail does not fail closed.** When `docker ps` errored, `grep` found nothing, and "found nothing" is indistinguishable from "no duplicate exists." The check evaluated to permission. Any validation built on an external command inherits that command's failure modes.

- **Image tags are movable pointers; image IDs are identity.** `:latest` follows the newest build. A container started from an earlier image keeps running that image regardless of where the tag has since moved. Same relationship as a git branch name to a commit hash.

- **A container lives exactly as long as its main process.** `CMD` is not configuration, it is the process the container exists to run. Choosing one that exits is choosing a container that dies.

- **A script that resolves paths from the working directory only works where it was developed.** `BASH_SOURCE` plus `dirname` gives a script its own location regardless of the caller's position in the filesystem.

- **`real` far exceeding `user` + `sys` means waiting, not computing.** 44 seconds wall-clock against a fraction of a second of CPU is the signature of a network stall.

- **Best practice loses to house style.** The commit message was initially drafted with a multi-paragraph body, against a repository whose convention is single-line subjects with reasoning kept in these phase documents. The right message is the one consistent with the commits around it.

---

## What This Demonstrates

- **Design decisions get revised on evidence, not on preference.** Unconditional rebuild was chosen for a defensible reason and reversed for a better one after the failure it did not account for actually occurred. The reversal, its cost, and the workaround are all documented rather than quietly applied.

- **Failure domains stay separated.** The Dockerfile was built and verified by hand before any script called it, so the first scripted failure could not have been an image problem. Same discipline that isolated dispatch in Phase 1.

- **Documentation is verified against the implementation, not against intent.** The README described a profile system that was never built. On a public repository, documentation that does not match the code is worse than none — it fails for the reader on their first attempt to use the tool.

- **The tool behaves correctly under constrained conditions.** Provisioning works from any directory and with no connectivity, which are the actual conditions a portable sandbox tool encounters.

---

## Security / Administration Relevance

**Fail-open validation is the defining failure of access control.** The `.Names` bug is the exact shape of a filter that errors and admits traffic, an authorization check that throws and returns permit, or a signature verifier that fails to load a key and reports valid. In each case the control appears present in the code, produces no error to an operator, and enforces nothing. Validation logic must distinguish "the check passed" from "the check could not run," and treat the second as a denial.

**Ordering controls before expensive operations limits exposure.** Refusing bad input before provisioning is the same principle as authenticating before allocating a session, or validating a request before hitting a database. Work performed for a request that should have been rejected is both wasted and, at scale, an amplification vector.

**Named resources are auditable; generated identifiers are not.** `--name` gives every sandbox a deterministic handle that a human can reason about and a later action can target. Phase 5's audit log depends on it — a log of container IDs describes what happened without describing what it was for.

**Container isolation is not a security boundary.** Containers share the host kernel; namespaces and cgroups constrain what a process sees and consumes, which contains an operator's own unproven code well and contains hostile code poorly. Genuinely adversarial workloads belong in a virtual machine or a hardened runtime such as gVisor or Kata Containers. The distinction is stated plainly in the README rather than left for a user to assume.

**Offline capability is availability.** A tool that silently depends on a remote service inherits that service's uptime, rate limits, and reachability. Confining the network dependency to first use converts a hard dependency into a one-time setup cost.

---

## Time Spent

~90 minutes

---

## Conclusion

`create` now builds the image when needed and starts a named, detached container from it, refusing empty and duplicate names before doing any work, from any working directory, with no network required once the image exists.

The first stage of the sandbox lifecycle is proven. Phase 3 replaces the `enter` stub with a shell into a running sandbox — which the `sleep infinity` decision and the named-container handle were both chosen to make possible.

---

## Glossary

**Base image** — the existing image a new image is built on top of, named by the `FROM` instruction.

**Build context** — the directory handed to `docker build`, whose contents are available to the build. Docker looks for a file named `Dockerfile` at its root unless told otherwise with `-f`.

**BuildKit** — Docker's current build engine, responsible for resolving base images, executing instructions, and caching layers.

**`CMD`** — the Dockerfile instruction naming the default process a container runs when started.

**Container** — a running instance created from an image, with its own isolated view of the filesystem, processes, and network.

**Content-addressable storage** — a scheme where data is identified by a hash of its own contents, so identical content always has the same address. Docker uses SHA256 digests this way to verify integrity and reuse unchanged layers.

**Detached mode (`-d`)** — starts a container in the background and returns the shell immediately, rather than attaching to its output.

**Digest** — the SHA256 hash identifying an exact image or layer. Unlike a tag, it never moves.

**`docker image inspect`** — reports metadata for an image in the local image store. Succeeds only if the image is present locally; makes no network request.

**`docker ps`** — lists containers. `-a` includes stopped ones.

**Dockerfile** — a plain-text file of build instructions, executed top to bottom by the build engine to assemble an image. A build script, not a configuration schema.

**Fail closed / fail open** — a control that denies when it cannot evaluate fails *closed*; one that permits fails *open*. Fail-open behavior is usually silent, which is what makes it dangerous.

**`FROM`** — the first instruction in a Dockerfile, naming the base image.

**Go template (`--format`)** — the templating syntax Docker uses to shape CLI output, written as `{{.Field}}`. Field names must match the struct being rendered exactly.

**`grep -qx`** — `-q` suppresses output and reports only success or failure through exit status; `-x` requires the pattern to match an entire line, not a substring.

**Guard clause** — a check at the top of a function that returns early when preconditions are not met, before the function's real work begins.

**Image** — a read-only filesystem template containers are created from. Built once, instantiated many times.

**Image ID** — the immutable identifier of a specific built image, independent of any tag pointing at it.

**Layer** — one filesystem change set produced by a Dockerfile instruction. Layers are cached and reused across builds when their inputs are unchanged.

**Layer cache** — the build engine's store of previously built layers, reused when an instruction and its inputs have not changed. Visible as `CACHED` in build output.

**`BASH_SOURCE`** — a bash array whose first element is the path of the script currently executing. More reliable than `$0` inside functions and sourced files.

**`dirname`** — strips the final component from a path, returning the directory portion.

**`return`** — exits a function with a status, leaving the rest of the script running. Distinct from `exit`, which terminates the entire script.

**`sleep infinity`** — a process that never exits, used as a container's main process to keep it running with no work to do.

**Tag** — a human-readable label pointing at an image, written `name:tag`. Tags are mutable and can be moved to a different image; the image itself is unchanged.

**`time`** — reports how long a command took: `real` is elapsed wall-clock time, `user` and `sys` are CPU time spent in user space and in the kernel. A large gap between `real` and the other two indicates waiting rather than computing.

**`>/dev/null 2>&1`** — discards a command's output entirely. `>/dev/null` sends stdout to the null device; `2>&1` redirects stderr to wherever stdout is currently going.
