# Phase 3 — Interactive Shell Into a Running Sandbox

*SandboxForge build log — Phase 3 of 5*

---

## Objective

Replace the `enter` stub with a working interactive shell inside a running sandbox, so that leaving the shell returns the operator to the host without stopping the container.

**Skills practiced:** `docker exec` versus `docker run`, interactive and TTY attachment, container state inspection, layered guard clauses, error message design, syntax validation with `bash -n`.

**Why it matters:** `create` proved a sandbox can be provisioned. Until an operator can get inside one, the tool provisions containers nobody uses. This phase also cashes in a Phase 2 decision: `CMD ["sleep", "infinity"]` was chosen specifically so a container would still be alive when `enter` arrived two phases later.

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

Entering a sandbox looks like one command. It carries three separate questions, and answering them as one produces a tool that is technically correct and practically useless.

Does the sandbox exist at all? Is it currently running? Only if both are true is there something to attach to. A tool that collapses these into a single "cannot enter" message forces the operator to go run `docker ps -a` themselves to find out which situation they are in, which is the work the tool was supposed to do for them.

The first version of this phase collapsed them. The second did not, and the reason it changed is documented below.

---

## Technical Concepts Covered

- `docker exec` versus `docker run` and what each creates
- Additional processes inside an existing container
- Interactive mode (`-i`) and stdin attachment
- TTY allocation (`-t`) and terminal behavior
- Container hostname defaulting to the short container ID
- Container state: created, running, stopped
- `docker start` and `docker stop`
- Layered guard clauses and check ordering
- Distinguishing absence from wrong state
- Error messages that carry a remediation
- `exit` as a shell builtin, and which process it ends
- Root inside a container versus root on the host
- `bash -n` syntax validation before execution

---

## Commands Used

```bash
# Provision a sandbox to work with
./bin/sandboxforge.sh create devbox

# Enter it and confirm the environment is not the host
./bin/sandboxforge.sh enter devbox
whoami
cat /etc/os-release
ls /
exit

# Confirm leaving the shell did not stop the container
docker ps

# Exercise each guard
./bin/sandboxforge.sh enter
./bin/sandboxforge.sh enter ghostbox
docker stop devbox
./bin/sandboxforge.sh enter devbox
docker start devbox

# Validate syntax after an edit broke the script
bash -n bin/sandboxforge.sh
```

---

## Procedure

1. **Added the `enter_sandbox()` skeleton** below `create_sandbox()` and above `main()`, for the same reason as Phase 2: the function must be defined before `main "$@"` executes at the bottom of the file.

2. **Reused the established opening.** `local name="$1"` and the empty-name guard are structurally identical to `create_sandbox`. The message names `enter` rather than `create`, because an operator running several subcommands needs to know which one refused.

3. **Added a running check.** `docker exec` can only attach to a live container, so `docker ps` without `-a` was used, negated with `!`, to refuse when the name is not among the running containers. This is the inverse of the `create` duplicate check, which used `-a` and refused when the name *was* found.

4. **Added the exec call.** `docker exec -it "$name" bash` starts a second process inside the already-running container and attaches the terminal to it. `-i` keeps stdin open so typed input reaches the shell. `-t` allocates a TTY, which supplies the prompt, line editing, and signal handling.

5. **Wired the function into the dispatch table**, replacing the `enter` stub with `enter_sandbox "${1:-}"`.

6. **Verified from inside.** `whoami` returned `root`, `/etc/os-release` reported the image's Ubuntu, and `ls /` showed a complete filesystem belonging to the container. The prompt itself changed to `root@b877efea122f:/#`, since a container's default hostname is its own short ID.

7. **Verified the exit behavior.** `exit` returned to the host prompt and `docker ps` still listed `devbox` as `Up`, confirming the Phase 1 decision not to build an `exit` subcommand. `exit` is bash's builtin ending the process `docker exec` started. The container's `sleep infinity` was never involved.

8. **Split the state check into two guards** after testing revealed the single message was ambiguous (documented below).

9. **Validated and retested** with `bash -n` and a full pass through all three guard paths.

---

## Results

**What worked:**

- `enter <name>` opens a root shell inside the named sandbox and returns to the host on `exit`, with the container still running.
- Each of the three failure paths produces a distinct, accurate message.
- The stopped-sandbox message names the exact command that fixes the situation.

**What didn't (and what it taught):**

**Bug 1 — unclosed quote, reported at the end of the file.** After adding the second guard, the script failed with `line 61: unexpected EOF while looking for matching '"'`. Line 61 is the last line of the file. The actual fault was an `echo` several lines earlier whose closing `"` had been left off before the `>&2` redirect. Bash consumed everything after the opening quote looking for its pair and ran out of file.

This is the identical failure documented in Phase 1, in the identical form: **"unexpected EOF" reports where the parser gave up, not where the mistake is.** Knowing the rule did not prevent making the mistake. It did make the fix immediate, which is what a documented failure mode is actually worth.

**Bug 2 — a missing flag that made the fix pointless while appearing to work.** The two new guards were supposed to ask different questions: does the sandbox exist at all (`docker ps -a`), and is it running (`docker ps`). The first was written without `-a`, so both asked whether the container was running.

The result parsed cleanly, ran without error, and produced a confidently wrong answer: stopping `devbox` and entering it reported `no sandbox named 'devbox'`, about a container that plainly existed. The second guard had become unreachable, and nothing in the script's behavior indicated that.

**A flag is not a detail when the flag is the entire difference between two checks.** This belongs to the same family as the `.Names` bug in Phase 2: validation logic that looks present, runs without complaint, and enforces something other than what was intended. Caught only by testing the specific case the check existed to handle.

**Design reversal — one message split into two, prompted by trying to say what happened out loud.** The first version used a single message, `sandbox 'X' is not running`, covering both a sandbox that does not exist and one that exists but is stopped. The decision to collapse them was deliberate, on the reasoning that nothing in the tool stops containers yet, so the stopped state would be rare until `stop` and `start` are built.

Describing the test run afterward produced this sentence: *"then enter ghostbox failed because ghostbox isnt running it doesnt exist yet."*

The self-correction mid-sentence is the finding. The person who wrote the code could not describe which of the two situations had occurred without amending himself, because the message did not distinguish them. Splitting the check cost four lines.

The second message was also given a remediation, `(docker start devbox)`, on the principle that **an error message which only says what is wrong is half an error message.** When `sandboxforge start` exists, that parenthetical becomes the tool's own command.

---

## Evidence

Entering a sandbox and confirming the environment:

```
$ ./bin/sandboxforge.sh enter devbox
root@b877efea122f:/# whoami
root
root@b877efea122f:/# cat /etc/os-release
PRETTY_NAME="Ubuntu 24.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION_CODENAME=noble
ID=ubuntu
root@b877efea122f:/# ls /
bin  boot  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
root@b877efea122f:/# exit
exit
```

The container survives the shell exiting:

```
$ docker ps
CONTAINER ID   IMAGE                      COMMAND            STATUS              NAMES
b877efea122f   sandboxforge-base:latest   "sleep infinity"   Up About a minute   devbox
```

All three guard paths after the split:

```
$ ./bin/sandboxforge.sh enter
sandboxforge: enter requires a sandbox name

$ ./bin/sandboxforge.sh enter ghostbox
sandboxforge: no sandbox named 'ghostbox'

$ docker stop devbox
devbox
$ ./bin/sandboxforge.sh enter devbox
sandboxforge: sandbox 'devbox' exists but is stopped (docker start devbox)
```

The same stopped-container test before the split, showing the wrong answer produced by the missing `-a`:

```
$ docker stop devbox
devbox
$ ./bin/sandboxforge.sh enter devbox
sandboxforge: no sandboxnamed 'devbox'
```

---

## Key Takeaways

- **An error message that only says what is wrong is half an error message.** State plus remedy is what turns a refusal into help. `(docker start devbox)` is a command the operator can run immediately.

- **Absence and wrong state are different problems and deserve different messages.** "Does not exist" and "exists but is stopped" call for different actions. Collapsing them pushes diagnostic work back onto the operator.

- **If you cannot describe your tool's behavior in one sentence, the behavior is ambiguous, not your sentence.** The design changed because a spoken description of a test run required a mid-sentence correction.

- **A flag can be the entire meaning of a check.** `docker ps` and `docker ps -a` are one character apart and ask different questions. Dropping it produced code that parsed, ran, and lied.

- **`docker exec` adds a process to a container. `docker run` creates a container.** Everything about `enter` follows from that distinction, including why the container has to already be running.

- **Knowing a failure mode does not prevent it, it shortens it.** The unclosed-quote error was documented in Phase 1 and made again in Phase 3. The documentation turned a hunt into a thirty-second fix.

---

## What This Demonstrates

- **Design decisions get tested from the operator's seat, not the code's.** The guard split was not driven by a principle about error messages. It was driven by using the tool and noticing the output failed to answer the question being asked of it.

- **Earlier decisions are load-bearing and get verified late.** `sleep infinity` was chosen in Phase 2 for a reason that could not be proven until Phase 3. The `exit` test is the receipt for it.

- **Repeat failures are documented rather than hidden.** Making the same mistake twice across phases is recorded here because the useful information is how much faster it was resolved the second time.

- **Validation runs before execution on a tool that operates on containers.** `bash -n` parses without running, which matters more with each phase, since Phase 4 adds a subcommand whose entire job is destroying things.

---

## Security / Administration Relevance

**Ordered checks must move from broadest to narrowest.** Existence is checked before state, because a stopped-container message about a container that was never created is worse than no message. The same ordering discipline governs any layered check: verify the subject exists before reasoning about its properties.

**Error messages are an operator interface, and vague ones cost time during incidents.** "Access denied" without naming the missing permission, or "connection failed" without naming the endpoint, are the same defect as "is not running" covering two states. Diagnostic burden not carried by the tool is carried by a person, usually under pressure.

**Root inside a container is host root, constrained by namespaces.** `whoami` returning `root` is not an artifact of the sandbox being a toy. It is UID 0 with namespace and cgroup restrictions applied. That is adequate for containing an operator's own unproven code and inadequate against a kernel exploit, which is the distinction the README already draws between an isolation boundary and a security boundary. Adding a non-root user to the image is a planned hardening step.

**`exec` into a running container is the container equivalent of an interactive login, and carries the same audit question.** Anyone who can reach the Docker socket can open a root shell in any container on the host. Phase 5's audit log records when this tool was used to do so, which is the reason the log is in the plan at all.

**Syntax validation is a control on destructive tooling.** `bash -n` costs nothing and catches an unbalanced quote before the interpreter discovers it partway through an operation. On a script whose next phase removes containers, discovering a parse error mid-execution means discovering it after something has already been torn down.

---

## Time Spent

40 minutes

---

## Conclusion

`enter` opens an interactive root shell inside a running sandbox and returns cleanly to the host, refusing with a specific message when the name is missing, unknown, or stopped.

Three of five phases are complete and the lifecycle is usable end to end except for teardown. Phase 4 replaces the `destroy` stub, which is the first subcommand that removes something rather than creating or inspecting it, and the first one where a guard failing open costs more than an error message.

---

## Glossary

**`docker exec`** — starts an additional process inside a container that is already running. Creates nothing new. Requires the container to be in the running state.

**`docker start` / `docker stop`** — move an existing container between the stopped and running states without destroying or recreating it. The container keeps its filesystem, name, and identity across both.

**`exit`** — a shell builtin that ends the current shell process. Inside a sandbox it ends only the shell that `docker exec` started, leaving the container's main process untouched.

**Interactive mode (`-i`)** — keeps stdin open and connected, so input typed at the terminal reaches the process inside the container. Without it a shell starts, reads nothing, and exits.

**Namespace** — a kernel feature that gives a process its own isolated view of a system resource such as the filesystem, process table, hostname, or network. Namespaces are what make a container's `ls /` show its own root rather than the host's.

**PID 1** — the first process in a container's process namespace, started from the image's `CMD`. The container's lifetime is tied to it: when PID 1 exits, the container stops.

**TTY (`-t`)** — a terminal device. Allocating one gives the process a shell prompt, line editing, command history, and signal handling such as Ctrl-C. Without it a shell runs but behaves as though it were being piped input from a file.
