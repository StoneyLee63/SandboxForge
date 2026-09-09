# Phase 4 — Teardown with a Confirmation Gate

*SandboxForge build log — Phase 4 of 5*

---

## Objective

Replace the `destroy` stub with complete removal of a sandbox, container and anonymous volumes both, gated behind a confirmation prompt so an irreversible action cannot happen from a single mistyped command.

**Skills practiced:** `docker rm` and its force and volume flags, the `read` builtin, `[[ ]]` test syntax and operator spacing, exit status semantics for deliberate cancellation, output stream discipline, minimizing checks to those that change behavior.

**Why it matters:** every subcommand before this one creates or inspects. This is the first that removes. A guard failing open in `create` produces a confusing error message. A guard failing open here destroys a container someone was working in. It also completes the v1 scope set at the start of the build: `create` to `enter` to `destroy`, working end to end.

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

Teardown is an awkward thing to design for a tool whose entire premise is disposability. Destroying a sandbox is not the dangerous edge case, it is the intended workflow. Make one, break things inside it, throw it away. A confirmation prompt taxes the normal path to guard against a rare mistake, and it makes the subcommand unusable from a script or a cleanup loop.

The counter-argument is that the tool has no record of anything it does. There is no log to consult after a mistaken teardown, because the audit log is Phase 5. Nothing catches the error, and nothing reconstructs what was lost.

The prompt went in. The reasoning that produced that decision, including the reasoning that initially argued against it, is documented below, because the mistake in it is the useful part.

---

## Technical Concepts Covered

- `docker rm` and permanent container removal
- Force removal (`-f`) of running containers
- Anonymous volume removal (`-v`) and orphaned volume accumulation
- The `read` builtin for interactive input
- Raw mode (`-r`) and prompt strings (`-p`)
- `[[ ]]` operator spacing as syntax rather than style
- Logical AND (`&&`) inside a test construct
- Exit status semantics: cancellation is success, not failure
- Suppressing stdout while preserving stderr
- Consistent output voice across a CLI's messages
- Minimizing checks to those that change behavior
- Safe-by-default design with a planned explicit override

---

## Commands Used

```bash
# Validate before running anything destructive
bash -n bin/sandboxforge.sh
echo $?

# Full teardown path
./bin/sandboxforge.sh create tempbox
./bin/sandboxforge.sh destroy tempbox    # answered n
docker ps
./bin/sandboxforge.sh destroy tempbox    # answered y

# Prove removal rather than a stop
docker ps -a

# Exercise the guards
./bin/sandboxforge.sh destroy tempbox
./bin/sandboxforge.sh destroy
```

---

## Procedure

1. **Added the `destroy_sandbox()` skeleton** below `enter_sandbox()` and above `main()`, consistent with the placement of the previous two functions.

2. **Reused the opening pattern.** `local name="$1"` and an empty-name guard whose message names `destroy` specifically.

3. **Added a single existence guard** using `docker ps -a`, and deliberately no running-state check. `enter` needed both, because attaching requires a live container. `destroy` does not care: `-f` kills a running container and removes a stopped one, so the two states lead to the same action. A check whose branches converge is dead weight, and dead weight in validation is another thing that can fail open.

4. **Added the confirmation prompt** using `read -r -p`, storing the answer in a `local` variable and treating anything other than `y` or `Y` as a cancellation. `-r` disables backslash escape processing, which should be the default habit for any `read`. `[y/N]` follows the convention that the capitalized letter is what a bare Enter selects.

5. **Returned `0` on cancellation.** The operator asked the tool to stop and it stopped, which is the tool working correctly. Returning non-zero would tell a calling script that something failed.

6. **Added the removal and a confirmation message.** `docker rm -v -f "$name" >/dev/null` discards Docker's own output, and the tool prints its own `sandboxforge: destroyed` line instead. Every message the tool emits now begins with the same prefix, so an operator scanning output always knows what is speaking. Only stdout is suppressed. A genuine failure from `docker rm` still reaches the terminal on stderr.

7. **Wired the function into the dispatch table**, replacing the last stub with `destroy_sandbox "${1:-}"`.

8. **Validated with `bash -n` before running**, then tested all five paths: cancel, confirm, verify removal, nonexistent name, missing name.

---

## Results

**What worked:**

- Answering `n` cancels cleanly and leaves the container running, verified with `docker ps`.
- Answering `y` removes the container completely. `docker ps -a` no longer lists it at all, which distinguishes removal from a stop.
- Both guards refuse with their own messages and without prompting.
- All of the tool's output now shares one prefix and one voice.

**What didn't (and what it taught):**

**Bug 1 — two typos in one test expression.** The confirmation check was written as:

```bash
if [[ "$reply" != "y": && "$reply" !="Y" ]]; then
```

A stray `:` after the first value, and no space between `!=` and `"Y"`.

The second is the instructive one. **Inside `[[ ]]`, whitespace is syntax, not formatting.** Bash splits the test into words and then decides what each word means. Separated by a space, `!=` is its own word and is recognized as the not-equal operator. Glued to its operand as `!="Y"`, it becomes one meaningless word and the test breaks. This is the same rule that makes `[[$x = 1]]` fail while `[[ $x = 1 ]]` works, and it is worth knowing as a rule rather than rediscovering it each time.

Caught by `bash -n` before the script ran, which is the entire argument for parsing before executing on a tool that removes things.

**Design reversal — a confirmation prompt, added after the argument against it turned out to rest on something that does not exist.**

The initial recommendation was to skip the prompt. The reasoning: these are disposable environments, so teardown is the happy path rather than the danger; a prompt on every removal taxes normal use; and prompts break automation, since a subcommand that blocks on input cannot run in a script or a cleanup loop. The protection, the argument went, should be the Phase 5 audit log rather than a gate, because for genuinely disposable resources a record of what happened beats a prompt that gets muscle-memoried away.

That reasoning has a hole in it. **The audit log is Phase 5. It does not exist.** Trading a real control for a planned one leaves the current version with neither. In v1, used interactively by one person with no logging, nothing at all catches a mistaken teardown.

The question that surfaced it was simple: for a v1, shouldn't it have a prompt?

The resolution is the standard pattern for destructive operations: **safe by default, explicit flag to override.** `rm` prompts in interactive mode and `rm -f` does not. The prompt goes in now, and a `--force` flag gets added when automation or the audit log arrives, so the escape hatch is something a person deliberately types rather than the default behavior.

The generalizable error is worth naming: **a compensating control that has not been built yet cannot be counted as mitigation.** Planned controls appear in risk assessments constantly and protect nothing until they ship.

---

## Evidence

Cancellation leaves the sandbox untouched:

```
$ ./bin/sandboxforge.sh create tempbox
4dbecb68d270726046db3bbdf3de5a401510f6e4955ba4f81f7e5362b2a92df1

$ ./bin/sandboxforge.sh destroy tempbox
Destroy sandbox 'tempbox'? [y/N] n
sandboxforge: cancelled

$ docker ps
CONTAINER ID   IMAGE                      COMMAND            STATUS          NAMES
4dbecb68d270   sandboxforge-base:latest   "sleep infinity"   Up 12 seconds   tempbox
```

Confirmation removes it, and `docker ps -a` proves removal rather than a stop:

```
$ ./bin/sandboxforge.sh destroy tempbox
Destroy sandbox 'tempbox'? [y/N] y
sandboxforge: destroyed 'tempbox'

$ docker ps -a
CONTAINER ID   IMAGE         COMMAND    CREATED      STATUS                  NAMES
82667ea790cf   hello-world   "/hello"   2 days ago   Exited (0) 2 days ago   interesting_hypatia
```

`tempbox` is absent from a listing that includes stopped containers. The only remaining entry is the `hello-world` container from the Phase 0 engine verification.

Both guards:

```
$ ./bin/sandboxforge.sh destroy tempbox
sandboxforge: no sandbox named 'tempbox'

$ ./bin/sandboxforge.sh destroy
sandboxforge: destroy requires a sandbox name
```

---

## Key Takeaways

- **A compensating control that has not shipped is not a control.** Skipping the prompt was justified by pointing at an audit log that is still a phase away. Until it exists, the version in front of you has no protection at all.

- **Safe by default, explicit flag to override.** This is the settled pattern for destructive operations, and it puts the burden on the person choosing to bypass the safety rather than on the person who wanted it.

- **Only check what changes behavior.** `destroy` skips the running-state check because `-f` handles both states identically. Every unnecessary check is another thing that can be written wrong and fail open.

- **Cancellation is success.** Exit status describes whether the tool did its job, not whether the outcome was action. A deliberate stop returns `0`.

- **Inside `[[ ]]`, whitespace is syntax.** `!=` needs to stand alone as a word to be recognized as an operator.

- **Silence the routine output, never the errors.** `>/dev/null` on `docker rm` hides its ordinary chatter while leaving stderr intact, so a real failure still reaches the operator.

- **One tool, one voice.** Every message begins with `sandboxforge:`, so a person reading a terminal full of output always knows which program is talking.

---

## What This Demonstrates

- **An argument gets abandoned when its premise fails, not when it loses.** The case against the prompt was internally coherent and rested on a control that was not built. Identifying that is a different skill from having the right instinct in the first place, and both showed up here.

- **Validation precedes execution on destructive tooling.** `bash -n` caught a broken test expression before a single container was touched. On a subcommand whose job is removal, discovering a syntax error at runtime means discovering it partway through.

- **Guard design is subtractive as well as additive.** The interesting decision in this function was leaving a check out, because its two outcomes led to the same action.

- **The v1 scope closed as specified.** `create`, `enter`, and `destroy` work end to end, from any directory, with no network required after first build, with every path guarded and every message naming both the problem and the remedy.

---

## Security / Administration Relevance

**Destructive operations get a gate, and the bypass is explicit.** This is the same posture as a delete confirmation in an admin console, a two-person rule on production changes, or `--yes-i-really-mean-it` flags in cluster tooling. The design principle is that the default protects, and removing the protection is a deliberate, visible act.

**Planned controls provide no protection.** A risk register listing a logging capability that is not yet deployed describes an intention, not a mitigation. The Phase 5 audit log will be a genuine control the day it ships and is worth nothing before then. This applies to compensating controls generally, and it is a common way for a security posture to look stronger on paper than it is in production.

**Irreversible actions deserve different treatment from reversible ones.** `create` failing is recoverable by running it again. `destroy` failing in the wrong direction is not. Ordering the safeguards by blast radius rather than by how often the code runs is the correct instinct.

**Suppressing output is a decision about what an operator can see.** Discarding stdout while leaving stderr intact keeps routine noise down without hiding failures. Blanket redirection that swallows both is how failed operations get mistaken for successful ones in automated environments.

**Consistent message prefixes matter for log parsing and incident review.** When every line a tool emits is identifiable as its own, output can be filtered, attributed, and searched. Mixed output from a tool and the commands it wraps is ambiguous the moment more than one thing is running.

---

## Time Spent

40 minutes

---

## Conclusion

`destroy` removes a sandbox and its anonymous volumes after a confirmation gate, refusing on a missing or unknown name, and reporting the result in the tool's own voice.

This closes v1 as scoped: `create` builds an image if needed and starts a named sandbox, `enter` opens a shell inside a running one, `destroy` takes it away. The lifecycle works from any working directory, with no network once the image exists, with every entry point guarded before it does work.

Phase 5 is the audit log, the last item in the original plan and the control this phase's design argument leaned on prematurely. After that, the deferred items: a `--force` flag for `destroy`, a `rebuild` subcommand for Dockerfile changes, `stop` and `start`, `list` and `status`, the profile system, and a non-root user in the image.

---

## Glossary

**Anonymous volume** — a storage volume Docker creates for a container without a name of its own. Not removed when the container is deleted unless `-v` is passed, which is how orphaned volumes accumulate on a host.

**Compensating control** — a safeguard used in place of another. Only counts as protection once it actually exists and is operating.

**`docker rm`** — permanently deletes a container and its writable layer. Distinct from `docker stop`, which leaves the container in place.

**Force removal (`-f`)** — allows `docker rm` to delete a running container by killing its main process first. Without it, `docker rm` refuses to touch a running container.

**`read`** — the Bash builtin that pauses execution, reads a line of input from the terminal, and stores it in a variable. `-r` disables backslash escape processing and should be used by default. `-p` prints a prompt string without a separate `echo`.

**Safe by default** — a design posture where the protective behavior is what happens with no extra arguments, and bypassing it requires an explicit flag.

**`[y/N]`** — the convention for indicating a default in a prompt. The capitalized option is what a bare Enter selects.
