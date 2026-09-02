# Harness integrity

The rules a measurement harness must satisfy before any number it produces may be reported.

Read this before writing a benchmark, a probe, or a check that a gate works. `/performance:snapshot`
and `/performance:verify` both apply it; it is not a standalone skill because it is a discipline
applied inside measurement, not a thing you invoke on its own.

## Why this file is the first thing in this plugin

One session, optimizing a single hook, produced **five verification harnesses that each returned a
confident wrong answer rather than an error**. Every one was caught only because something explicitly
re-checked it. Four of the five were checks written *specifically to avoid being fooled*: the
meta-checks were less reliable than the thing they were checking.

| # | Harness | Reported | Actually did |
|---|---|---|---|
| 1 | spawn census via a `PATH` shim | "no improvement" | `mktemp -d` put a fresh directory on `PATH` every run, and the subject cached keyed on `PATH`. Every run was a forced cache miss. It measured its own randomization. |
| 2 | hard-link identity probe | "0 divergences" | `os.link` failed cross-volume on Windows and fell back to `shutil.copyfile`. A copy is a different file, so the probe reported a green result for a case it never exercised. |
| 3 | discrimination check (shell) | "NOT DISCRIMINATING" | A `D:/...` path handed to bash resolves nowhere under MSYS. Both arms exited 127 and the grep found nothing in either. |
| 4 | discrimination check (repeat) | "NOT DISCRIMINATING" | Same trap, a second harness. Fixing the path form immediately showed FAIL-without / PASS-with. |
| 5 | discrimination check (python) | "NOT DISCRIMINATING" | Restored via `git checkout --` while the fix under test was **uncommitted**. The restore silently reverted the fix, so the "with fix" arm ran without it, and the work was destroyed. |

None of these are knowledge gaps. They are all "the measurement was wrong in a way that looked
right". A workflow that measures without enforcing the rules below mostly generates confident
numbers, which is worse than generating none.

## The rules

### 1. A harness must prove it is not measuring itself

Anything the harness injects into the environment under test (`PATH` entries, temp directories,
environment variables, working directory) is either **fixed across runs** or **provably irrelevant
to the subject's behavior**.

Cases 1 and 3/4 above are the same root cause seen twice: the harness changed `PATH` in a way that
mattered to the subject.

Check it by running the harness twice against an **unchanged** subject. If the two runs disagree
beyond the host's characterized noise, the harness is a variable, not an instrument.

### 2. A probe must assert its own precondition

If a test depends on a hard link, a symlink, a particular filesystem, a permission, or a binary being
present, it must **FAIL when that precondition is unmet**. It must never silently degrade into a
weaker test that passes.

Case 2 is the canonical shape: a `try: os.link / except: shutil.copyfile` fallback turned a
link-identity probe into a probe of something else entirely, and reported success.

A skip is acceptable **only** when the skipped branch is not the point of the test. A skip that
vacates the only discriminating assertion is a false green. This repo gates that shape mechanically
in `scripts/check-discriminating-test-skips.sh`; annotate a load-bearing branch with
`# discriminating-skip-required:` so a later `skip_case` there is refused.

### 3. A discrimination check must verify its own patch applied

A check that a gate works has two arms: **without** the fix it must fail, **with** the fix it must
pass. Both arms failing identically is the most common failure mode, and it reads as "not
discriminating" when it actually means "the harness never ran".

So assert three things, not two:

1. the negative arm produces the failing outcome,
2. the positive arm produces the passing outcome, and
3. **the two arms produced different output.**

Point 3 is the one that catches cases 3, 4 and 5. Without it, a harness where both arms exit 127
reports a clean, confident, wrong verdict.

Assert that the patch changed something before running the arm. A patch that silently applied
nothing is arm 3's failure mode.

### 4. Restore from saved bytes, not from version control

Take an in-memory or on-disk copy of the file **before** editing it, and restore from that copy.

`git checkout --` is correct only when the code under test is already committed, and is **actively
destructive** otherwise. Case 5 destroyed the work it was verifying.

Verify the restore rather than assuming it: an empty `git diff` against the commit, or a byte
comparison against the saved copy. "I restored it" is not evidence.

### 5. Commit before you verify

This makes the restore path safe and makes an accidental clobber recoverable. It is the cheapest
mitigation for rule 4 and costs nothing.

### 6. Windows drive-letter paths are a first-class hazard

Three of the five cases involve `D:/...` or backslash handling, and an independent verifier hit the
same trap on its own harness.

- A `D:/...` path handed to `bash` under MSYS resolves nowhere. Use the POSIX form (`/d/...`).
- Windows `PATH` entries in drive-letter form break bash's colon-separated parsing, because the colon
  after the drive letter is read as a separator.
- `os.link` fails across volumes; `shutil.copyfile` does not, which is exactly what makes the
  fallback dangerous.

On a mixed MSYS/native host this is not an edge case. It is the default hazard.

## Two more traps, from the same session

- **`$(...)` command substitution is a process spawn on MSYS.** A "builtins-only" hot path that
  reports via stdout still costs a full process. A spawn-count harness that ignores its own
  substitutions undercounts.
- **`${var: -N}` returns the empty string when the string is shorter than N** in bash. This silently
  collapsed a per-plugin cache key onto one shared file, which a harness would read as a cache that
  works.

## Checklist

Before reporting any number:

- [ ] The harness injects nothing into the subject's environment that varies between runs.
- [ ] Two runs against an unchanged subject agree within the host's characterized noise.
- [ ] Every precondition the probe depends on is asserted, and fails rather than degrading.
- [ ] Any discrimination check asserts that its two arms **differ**.
- [ ] The code under test was committed before the check ran.
- [ ] Restores came from saved bytes, and the restore was verified.
- [ ] Every path handed to a shell is in that shell's own path form.
