# Phase 5 — Audit Log

*SandboxForge build log — Phase 5 of 5*

---

## Objective

Record every action the tool takes, successful or refused, as a timestamped line in a log that persists independently of the sandboxes it describes.

**Skills practiced:** shared helper functions, multiple positional parameters, `$HOME` and per-user application state, `mkdir -p`, `date` format strings and ISO 8601, `printf` versus `echo`, append versus overwrite redirection, log format design, and the limits of `bash -n`.

**Why it matters:** this is the control Phase 4's design argument leaned on before it existed. It is also what makes the `--name` decision from Phase 2 pay off, because a log of container IDs records what happened without recording what it was for. Phase 5 closes the original plan.

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

An audit log is three design questions before it is any code.

**Where does it live?** Inside the repository means it gets committed, which puts a record of local activity into a public portfolio. `/var/log` is the conventional system location but requires root, which is wrong for a tool that deliberately runs unprivileged. `~/.sandboxforge/` is the standard place for per-user application state, and it survives independently of any container or repository it describes. A log stored inside the thing it audits disappears with it.

**What goes in a line?** Enough to reconstruct events without being there, in a shape a parser can read.

**Does a refused action get logged?** This is the question that shapes the other two, and the answer taken here was yes, for a reason stated below.

---

## Technical Concepts Covered

- Shared helper functions called from multiple call sites
- Multiple positional parameters (`$1`, `$2`, `$3`)
- `$HOME` and portable paths
- Hidden directories and per-user application state
- `mkdir -p` and idempotent directory creation under `set -e`
- `date` format strings, ISO 8601, and UTC
- `printf` format strings versus `echo`
- Append (`>>`) versus overwrite (`>`) redirection
- Fixed-field log formats and no-value placeholders
- Logging access grants rather than completions
- The difference between syntax checking and semantic checking
- `shellcheck` as a static analyzer for shell

---

## Commands Used

```bash
# See the timestamp format before embedding it
date -u +%Y-%m-%dT%H:%M:%SZ

# Validate after each round of edits
bash -n bin/sandboxforge.sh
echo $?

# Test create's logging before repeating the pattern
./bin/sandboxforge.sh create
./bin/sandboxforge.sh create logtest
./bin/sandboxforge.sh create logtest
cat ~/.sandboxforge/audit.log

# Full end to end across all three actions
./bin/sandboxforge.sh enter ghostbox
./bin/sandboxforge.sh create logtest2
./bin/sandboxforge.sh enter logtest2
./bin/sandboxforge.sh destroy logtest2    # answered N, then y
cat ~/.sandboxforge/audit.log
```

---

## Procedure

1. **Settled the three design questions first.** Log at `~/.sandboxforge/audit.log`. Four fields per line: UTC timestamp, action, sandbox name, result. Refusals recorded alongside successes.

2. **Built `log_action()` above the other functions.** Helpers read better at the top, and everything else calls it. Three positional parameters instead of one: `action`, `name`, `result`.

3. **Resolved the log path through `$HOME`** rather than a hardcoded `/home/<user>`, so the tool works for whoever runs it. The leading dot in `.sandboxforge` follows the convention for application state, keeping it out of the way of a user's own files.

4. **Created the directory with `mkdir -p`.** The `-p` creates missing parents and, more importantly here, does not error when the directory already exists. Plain `mkdir` would fail on the second run, and under `set -e` that failure would kill the tool.

5. **Wrote the line with `printf` and `>>`.** `printf '%s %s %s %s\n'` with four values gives a fixed shape and an explicit newline. `>>` appends. `>` would truncate the file on every write, destroying the entire history each time the tool ran.

6. **Used UTC and ISO 8601** via `date -u +%Y-%m-%dT%H:%M:%SZ`. Logs get read on other machines, in other timezones, and correlated against other systems. Local timestamps make that guesswork.

7. **Wired the three create call sites and tested before continuing.** Same failure-domain discipline used for the Dockerfile in Phase 2. A wrong log format is cheaper to find across three call sites than eleven.

8. **Wired the remaining eight call sites** across `enter` and `destroy`, covering every guard refusal, the cancellation branch, and each success.

9. **Placed `enter`'s success log before `docker exec`, not after.** `docker exec` blocks until the operator leaves the shell, which could be hours. Logging afterward means an in-progress session appears nowhere, and a session never exited is never recorded at all. The log records the access being granted, the same way an authentication log records a login rather than a logout.

10. **Validated and ran the full path**, then read the log back as the test.

---

## Results

**What worked:**

- Every action across all three subcommands writes a four-field line.
- Every result type appears: `ok`, `refused`, `cancelled`.
- The log persists after the sandboxes it describes are destroyed.
- `mkdir -p` created the directory silently on first run and caused no error on every run after.

**What didn't (and what it taught):**

**Bug 1 — a call to a function that does not exist, which `bash -n` passed.** The cancellation branch of `destroy_sandbox` was written as `log_audit "destroy" "$name" "cancelled"`. The function is `log_action`.

`bash -n` reported no problem. That line is valid shell grammar, and bash cannot know at parse time whether a command named `log_audit` will exist at runtime. It would have failed with `log_audit: command not found` during a cancellation, and under `set -e` that failure would end the script.

**`bash -n` checks grammar, not meaning.** It catches an unbalanced quote or a missing `fi`. It cannot catch a misspelled function name, a wrong argument count, or a variable that is never set. A clean `-n` means parseable, not correct. That is a real limit on a tool leaned on throughout this build, and the correct next tool is `shellcheck`, a static analyzer that does resolve references and flags common shell traps.

**Bug 2 — a typo that survived four phases, found by reading the tool's own output.** Testing the logging surfaced this line:

```
sandobxforge: sandbox 'logtest' already exists
```

`sandobxforge`, transposed, in the duplicate-name guard written back in Phase 2. It had been read past repeatedly while working in that function. It was caught only because a test run put the string on screen next to correctly spelled output.

The lesson is about verification method rather than spelling: **rereading code you wrote does not find errors in code you wrote.** Running it and reading the output does. This is the same reason the guard split in Phase 3 came from describing behavior out loud rather than from reviewing the function.

**Design decision — refusals are logged, because the absence of a record is itself a blind spot.**

The question was whether a rejected action deserves a line. It does, and the reason is adversarial: a log containing only successes describes what the tool did, while a log containing refusals can show what someone *attempted*. Six refused `destroy` calls against names that do not exist is enumeration, someone probing to discover what is there. That pattern is entirely invisible in a success-only log.

This is the same reasoning behind logging failed authentication attempts everywhere, and it is often the failures that carry the signal.

**Design consequence — a result field, and a placeholder for missing values.** Once refusals are recorded, `destroy devbox` and `destroy ghostbox` cannot look identical, so the format needed a fourth field. And when the missing input *is* the name, that field cannot simply be blank, or the line has three fields where every other line has four. `-` is the conventional no-value placeholder in log formats, used by Apache and nginx for the same reason. **A format with a variable field count is not a format.**

---

## Evidence

The full log after a complete session:

```
2026-09-09T15:34:38Z create - refused
2026-09-09T15:35:07Z create logtest ok
2026-09-09T15:35:13Z create logtest refused
2026-09-09T15:50:37Z enter ghostbox refused
2026-09-09T15:50:52Z create logtest2 ok
2026-09-09T15:51:02Z enter logtest2 ok
2026-09-09T15:51:19Z destroy logtest2 cancelled
2026-09-09T15:51:35Z destroy logtest2 ok
```

The session reconstructs from eight lines without having been present. A create with no name. A sandbox made, then a duplicate attempt. An attempt to enter `ghostbox`, a name that appears nowhere else in the log and therefore was never created. A clean create, enter, cancelled destroy, and destroy.

That fourth line is the one the refusal decision exists for. In a success-only log it would be absent, and the record would show nothing but an orderly sequence of successful operations.

---

## Key Takeaways

- **Log refusals, not just successes.** A success-only log records what the tool did. Recording refusals is what makes attempted actions visible, and attempts are where probing shows up.

- **The terminal tells you what is happening. The log tells anyone what happened.** Terminal output is ephemeral, local to one person, and scrolls away. A log persists, outlives what it describes, and is readable by someone who was not there.

- **A log stored inside what it audits disappears with it.** `~/.sandboxforge/` outlives every container and the repository both.

- **`>` destroys a log. `>>` extends it.** One character between appending and total history loss on every write.

- **`bash -n` checks grammar, not meaning.** It cannot see an undefined function, a wrong argument count, or an unset variable. `shellcheck` is the tool for that class.

- **Rereading your own code does not find your own errors.** A four-phase-old typo surfaced the first time a test printed it on screen. Run it and read the output.

- **A format with a variable field count is not a format.** `-` in place of a missing value keeps every line parseable.

- **Log the grant, not the completion.** `enter` records access at the moment it is given, so a session in progress is visible rather than only a session that ended.

---

## What This Demonstrates

- **Design questions come before code, and one of them determines the others.** Deciding refusals were in scope is what forced a result field and a placeholder convention. Answering it later would have meant reworking the format after eleven call sites were written.

- **Reasoning is adversarial where it should be.** The refusal decision was not made for completeness. It was made because the person who cannot be seen in the log is the one worth seeing.

- **Verification methods are chosen deliberately.** `bash -n` before running, then real execution, then reading output rather than rereading source. Each catches a class the previous one cannot.

- **The plan finished as written.** Five phases, each with a checkpoint, each documented at the time rather than reconstructed afterward.

---

## Security / Administration Relevance

**Failed attempts often carry more signal than successful ones.** Authentication systems log failures universally, and for the same reason this tool does: a sequence of refusals against names that do not exist is a pattern, and it is invisible in a success-only record. Detection depends on recording things that did not work.

**Log timestamps belong in UTC.** Correlating events across systems, machines, and timezones is the ordinary case during an incident, and local time makes it guesswork. Every serious logging system defaults to UTC.

**Logs must outlive the systems they describe.** A log written inside a container is destroyed with the container, which means the record of a compromise is destroyed by the same action that ends it. Storing the log outside the audited boundary is the whole point of centralized logging, and this is the small version of that principle.

**This log is a record, not tamper-evident evidence, and that limit should be stated plainly.** It lives in the user's own home directory and is writable by that user. Anyone who can run the tool can also edit its history. Making it evidence would require append-only permissions, a separate service account, shipping lines to a remote collector, or all three. For a single-operator tool the record is the right scope, but calling it an audit trail without naming that limitation would overstate what it provides.

**Append-only behavior is a correctness requirement, not a preference.** `>` on a log file silently destroys everything before the current write. In a logging path, the difference between `>` and `>>` is the difference between a history and a single most-recent entry.

**Consistent, parseable log formats determine whether a log is usable at scale.** Fixed field counts, a stable order, and an explicit placeholder for missing values are what allow filtering, alerting, and correlation. Human-readable-only formats become unusable exactly when volume makes them matter.

---

## Time Spent

35 minutes

---

## Conclusion

Every action SandboxForge takes now writes a timestamped UTC line recording what was attempted, against which sandbox, and whether it succeeded, was refused, or was cancelled. The log lives outside everything it describes and survives it.

This closes the five-phase plan set at the start of the build. The tool provisions, enters, and destroys isolated sandboxes from any directory, without a network after first build, with every entry point guarded before it acts and every action recorded after.

Remaining backlog, all deferred deliberately and documented as such: a `--force` flag for `destroy`, a `rebuild` subcommand for Dockerfile changes, `stop` and `start`, `list` and `status`, the profile system, and a non-root user in the image.

---

## Glossary

**Append redirection (`>>`)** — adds output to the end of a file, preserving existing content. Distinct from `>`, which truncates the file to zero length before writing.

**Audit log** — a durable record of actions taken by a system, kept for later review rather than for immediate feedback.

**`date` format string** — the specification following `+` that controls `date` output. `%Y` year, `%m` month, `%d` day, `%H:%M:%S` time. `-u` selects UTC.

**Enumeration** — probing a system to discover what exists in it, typically by attempting operations against guessed names and observing which are refused differently.

**`$HOME`** — an environment variable set at login containing the path to the current user's home directory. Using it in place of a hardcoded path makes a script portable across users.

**ISO 8601** — the international standard date and time format, written here as `YYYY-MM-DDTHH:MM:SSZ`. The `T` separates date from time and `Z` denotes UTC.

**`mkdir -p`** — creates a directory along with any missing parents, and exits successfully if the directory already exists. The second behavior is what makes it safe to call repeatedly under `set -e`.

**`printf`** — writes formatted output using a format string with `%s` placeholders filled from its arguments. More predictable across systems than `echo`, and it adds no newline unless one is written explicitly.

**`shellcheck`** — a static analyzer for shell scripts. Resolves references, flags unquoted variables and common bash traps, and explains each warning. Catches the class of error `bash -n` cannot.

**Tamper-evident** — a record whose modification can be detected. A file writable by the same user who generates it is not tamper-evident, regardless of what it contains.

**UTC** — Coordinated Universal Time. The timezone-independent reference used for timestamps intended to be compared across systems.
