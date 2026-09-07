# Phase 1 — CLI Skeleton and Subcommand Dispatch

*SandboxForge build log — Phase 1 of 5*

---

## Objective

Build the command-line interface that SandboxForge's container operations will hang from: a script that recognizes its own subcommands, routes each to the correct handler, and rejects anything it doesn't know.

**Skills practiced:** Bash script structure, strict-mode error handling, positional parameter handling, pattern matching with `case`, stream separation, exit status conventions, git repository initialization.

**Why it matters:** Dispatch and container logic are two separate problems. Building them together means every failure has two possible causes. Phase 1 proves the routing in isolation, so that when Docker calls arrive in Phase 2, any failure belongs to Docker.

---

## Environment

- **Distribution:** Ubuntu 24.04.4 LTS (Noble Numbat)
- **Platform:** WSL2 on Windows
- **User Context:** Standard user with sudo privileges
- **Editors:** nano and VS Code
- **Repository:** `~/projects/flagships/sandboxforge`

---

## Scenario

A command-line tool needs a predictable interface before it does anything consequential. This one will eventually create and destroy containers, which means an unrecognized command must fail loudly rather than fall through silently — a tool that quietly does nothing when misused is worse than one that refuses, because the operator believes the work happened.

The task is to build that interface first and prove it independently.

---

## Technical Concepts Covered

- Shebang lines and interpreter resolution through `PATH`
- Bash strict mode: `set -e`, `set -u`, `set -o pipefail`
- Function definition and variable scoping with `local`
- Positional parameters and parameter expansion with defaults
- `shift` and argument consumption
- `case` pattern matching and match ordering
- Standard streams and file descriptor redirection
- Exit status conventions
- Executable permission bits
- Syntax validation with `bash -n`
- Git repository initialization and staged commits

---

## Commands Used

```bash
# Scaffold the project structure
mkdir -p ~/projects/flagships/sandboxforge/{bin,profiles,docs}
cd ~/projects/flagships/sandboxforge
git init
touch bin/sandboxforge.sh
chmod +x bin/sandboxforge.sh
ls -l bin/

# Inspect the file when behavior didn't match expectation
cat -n bin/sandboxforge.sh

# Validate syntax without executing
bash -n bin/sandboxforge.sh

# Functional tests
./bin/sandboxforge.sh
./bin/sandboxforge.sh bogus
./bin/sandboxforge.sh bogus 2>/dev/null
./bin/sandboxforge.sh create test-box
./bin/sandboxforge.sh enter test-box
./bin/sandboxforge.sh destroy test-box
./bin/sandboxforge.sh create
echo $?

# Commit the checkpoint
git add .
git commit -m "Phase 1: CLI skeleton with subcommand dispatch"
```

---

## Procedure

1. **Scaffolded the project** in the Linux filesystem rather than under `/mnt/c/`, where Windows-side permission translation prevents the execute bit from reliably persisting. Created `bin/`, `profiles/`, and `docs/` in a single command using brace expansion, initialized the git repository, and set the execute bit on the script.

2. **Established the interpreter and failure policy.** Added the shebang (`#!/usr/bin/env bash`, resolving bash through `PATH` rather than hardcoding a location) and enabled strict mode so the script exits on command failure, undefined variables, and failed pipeline stages.

3. **Built the entrypoint skeleton.** Defined `main()` with a `:` placeholder body — bash rejects an empty function body — and called it at the bottom with `main "$@"`, forwarding every argument as a separately quoted word.

4. **Built the rejection path before any working command.** Captured the subcommand into a `local` variable using `${1:-}` so that an invocation with no arguments would not trip `set -u`, consumed it with `shift`, and wrote a `case` statement containing only the wildcard branch: print to stderr, exit non-zero.

5. **Verified stream separation** by running the failing command with `2>/dev/null`, confirming the message disappeared and was therefore correctly written to file descriptor 2.

6. **Added the three subcommand branches** above the wildcard, each printing its intent and reading its sandbox name from `$1` — which now refers to the argument following the subcommand, because of the earlier `shift`.

7. **Tested the full command surface** — each subcommand with and without a name, plus an unrecognized command — and committed the working state.

---

## Results

**What worked:**

- All three subcommands route to their own branches and correctly read the sandbox name that follows them.
- Omitting the name produces the `<none>` fallback rather than an unbound-variable failure.
- Unrecognized commands and bare invocation both produce an error on stderr and exit status `1`.
- `2>/dev/null` suppressed the error message, confirming it was written to stderr and not stdout.

**What didn't (and what it taught):**

**Bug 1 — wrong default value.** Running the script with no arguments printed `unknown command '1'` instead of `unknown command ''`. The assignment had been typed as `${1:-1}` rather than `${1:-}`. In `${VAR:-default}`, everything after `:-` is the fallback value, so the fallback had become the literal character `1`.

The error message was accurate the entire time — `cmd` really did contain `1`. The mistake was reading unexpected output as noise instead of as a precise report of program state. Diagnosed by reading the file with `cat -n` rather than relying on memory of what was typed.

**Bug 2 — unclosed parameter expansion.** After adding the subcommand branches, the script failed with `line 25: unexpected EOF while looking for matching '"'`. Line 25 is the end of the file. The actual fault was on the `create` branch, where `${1:-<none>}` had been closed with `]` instead of `}`. With no closing brace, bash consumed the remainder of the file searching for one — through the closing quote, through the rest of the `case`, to EOF.

The lesson generalizes: **"unexpected EOF" reports where the parser gave up, not where the error is.** The fault is always an unclosed delimiter earlier in the file. This is also the failure that justified adding `bash -n` to the workflow — it parses without executing, which matters for a tool whose eventual job is destroying containers.

---

## Evidence

Full command surface after both fixes:

```
$ ./bin/sandboxforge.sh create test-box
[create] would create sandbox: test-box
$ ./bin/sandboxforge.sh enter test-box
[enter] would enter sandbox: test-box
$ ./bin/sandboxforge.sh destroy test-box
[destroy] would destroy sandbox: test-box
$ ./bin/sandboxforge.sh create
[create] would create sandbox: <none>
$ ./bin/sandboxforge.sh bogus
sandboxforge: unknown command 'bogus'
$ echo $?
1
```

Stream separation confirmed:

```
$ ./bin/sandboxforge.sh bogus 2>/dev/null
$
```

---

## Key Takeaways

- **Build the rejection path before the working paths.** With only the wildcard branch in place, the script is structurally incapable of silently accepting a command it doesn't handle. Every subcommand added afterward is a deliberate exception to refusal, rather than refusal being an afterthought that may never get written.

- **Wildcard position is not stylistic.** `case` evaluates patterns top to bottom and stops at the first match. `*)` matches everything, so any branch below it is unreachable. Same structural rule as a default-deny at the bottom of a firewall rule set.

- **`${VAR:-default}` puts the fallback after the `:-`.** Anything typed there becomes the literal fallback value. This was Bug 1 in its entirety.

- **"Unexpected EOF" points at surrender, not at the mistake.** The reported line number is where the parser ran out of file. The unclosed delimiter is always earlier.

- **Error output is data, not noise.** `unknown command '1'` was a correct report of a variable's contents. Reading it literally would have located the bug immediately.

- **Errors belong on stderr.** Writing them to stdout corrupts anything downstream that pipes or captures the tool's output. Verifiable in one command with `2>/dev/null`.

- **`"$@"` must be quoted.** Unquoted, an argument containing spaces is split into multiple arguments and the script silently operates on the wrong input.

---

## What This Demonstrates

- **Strict mode converts silent misbehavior into loud failure.** Default bash continues past errors and treats undefined variables as empty strings. For a tool that will run `docker rm "$name"`, an empty `$name` is not a harmless no-op — `set -u` is what stands between a typo and an unintended teardown.

- **`shift` establishes a consistent argument contract.** After the subcommand is consumed, every branch reads its own arguments beginning at `$1` without knowing or caring what invoked it. Each handler becomes independent of its position in the dispatch table.

- **Separating dispatch from execution isolates failure domains.** Because routing was proven with stubs, any Phase 2 failure is attributable to Docker rather than to argument handling.

---

## Security / Administration Relevance

**Unbound variables are a destructive-operation risk.** The canonical incident is a cleanup script running `rm -rf "$DIR"/` where `$DIR` was never set. `set -u` makes that fail immediately rather than execute against an unintended target. Any script that deletes, stops, or overwrites should enable it as a default posture.

**Ordered match evaluation with a terminal catch-all is the same pattern as a firewall policy.** Specific rules first, default-deny last. Reversing the order makes every specific rule unreachable while appearing correct on inspection — the failure mode is silence, not error.

**Stream separation matters for log integrity.** In automated pipelines, stdout typically carries data for downstream consumption and stderr carries diagnostics for operators and log aggregation. Errors written to stdout contaminate parsed output and can be missed entirely by monitoring configured to watch stderr.

**Syntax validation before execution is a control, not a convenience.** `bash -n` parses without running. On scripts that perform destructive operations, discovering a syntax error mid-execution means discovering it after some operations have already completed.

---

## Time Spent

~45 minutes

---

## Conclusion

Validated a working command-line interface with argument dispatch, default handling, stream-correct error reporting, and standard exit status conventions, committed as the repository's first checkpoint.

The interface is proven. Phase 2 replaces the `create` stub with real image builds and container starts, against a routing layer that no longer needs to be questioned when something breaks.

---

## Glossary

**Argument** — a value passed to a command, following the command name.

**`bash -n`** — parses a script and reports syntax errors without executing it. `-n` is *noexec*.

**Brace expansion** — shell syntax (`{a,b,c}`) that expands into multiple separate words before the command runs.

**`case` / `esac`** — bash's pattern-matching construct. Evaluates top to bottom, executes the first match. `esac` is `case` reversed.

**`cat -n`** — prints a file's contents to the terminal with numbered lines.

**`chmod`** — *change mode*. Sets a file's permission bits.

**Exit status (return code)** — the numeric result a process reports on completion. `0` means success; any non-zero value indicates failure. Readable as `$?`.

**Execute bit** — the permission that makes a file runnable. Visible as `x` in `ls -l` output. A script is executable because this bit is set, not because of its filename or contents.

**File descriptor** — a numbered channel a process reads from or writes to. `0` is stdin, `1` is stdout, `2` is stderr.

**Flag (option)** — a modifier passed to a command, conventionally prefixed with `-` (short form) or `--` (long form).

**Function** — a named, reusable block of commands.

**`local`** — declares a variable scoped to the function it appears in. Bash variables are global by default.

**`main()`** — by convention, the single entrypoint function that all execution routes through.

**Null command (`:`)** — a builtin that does nothing and returns success. Used as a placeholder where bash requires at least one command.

**Parameter expansion** — substituting a variable's value into a command, written `${VAR}`. `${VAR:-default}` substitutes *default* when `VAR` is unset or empty.

**Path** — the location of a file in the filesystem. *Absolute* paths begin at `/` and are unambiguous; *relative* paths resolve from the current working directory.

**`PATH`** — the environment variable listing directories the shell searches when locating a command by name.

**Positional parameter** — an argument referenced by position: `$1`, `$2`, and so on. `$@` is all of them.

**Repository (repo)** — a directory tracked by git, with history stored in a hidden `.git` subdirectory.

**Shebang (`#!`)** — the first line of a script, naming the interpreter the kernel should hand the file to.

**`shift`** — discards `$1` and renumbers the remaining positional parameters downward.

**Staging area** — git's holding zone. `git add` moves changes into it; `git commit` writes what it holds into history.

**stderr** — standard error, file descriptor 2. The channel for diagnostics and error messages.

**stdout** — standard output, file descriptor 1. The channel for a program's normal output.

**Strict mode** — the convention `set -euo pipefail`: exit on error, error on undefined variables, and fail a pipeline if any stage in it fails.

**Wildcard (`*`)** — a pattern matching any sequence of characters. As a `case` branch, it must be last, or it makes every branch below it unreachable.

**Working directory** — the directory a shell is currently operating in. Reported by `pwd`, changed with `cd`.
