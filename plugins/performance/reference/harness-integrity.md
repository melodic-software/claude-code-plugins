# Harness integrity

The rules a measurement harness must satisfy before any number it produces may be reported.

Read this before writing a benchmark, a probe, or a check that a gate works.
`/performance:snapshot` and `/performance:verify` both apply it.

## Harnesses that returned a confident wrong answer

The failures below are the source material for the rules. Each harness returned a confident wrong
answer rather than an error, and each was caught only because something explicitly re-checked it.
Most of them were checks written to avoid being fooled, which is the point: a meta-check is no more
reliable than the thing it checks.

| # | Harness | Reported | Actually did |
|---|---|---|---|
| 1 | spawn census via a `PATH` shim | "no improvement" | `mktemp -d` put a fresh directory on `PATH` every run, and the subject cached keyed on `PATH`. Every run was a forced cache miss. It measured its own randomization. |
| 2 | hard-link identity probe | "0 divergences" | `os.link` failed cross-volume on Windows and fell back to `shutil.copyfile`. A copy is a different file, so the probe reported a green result for a case it never exercised. |
| 3 | discrimination check (shell) | "NOT DISCRIMINATING" | A Windows path spelling handed to bash left both arms exiting 127, so neither arm ever reached the subject and the grep found nothing in either. Identical failure in both arms reads as "not discriminating". |
| 4 | discrimination check (repeat) | "NOT DISCRIMINATING" | Same trap, a second harness. Fixing the path form immediately showed FAIL-without / PASS-with. |
| 5 | discrimination check (python) | "NOT DISCRIMINATING" | Restored via `git checkout --` while the fix under test was **uncommitted**. The restore silently reverted the fix, so the "with fix" arm ran without it, and the work was destroyed. |
| 6 | hand-rolled interleaving harness (python) | 63 ms per sample, every sample | A bare `bash` under `subprocess` resolved by `PATH` order, per that run's own notes to WSL's `bash.exe` in the Windows `System32` directory, which cannot see a drive-letter path. Every sample exited 127 and was timed as a fast, clean run. Caught only by checking exit codes. The bundled `scripts/ab.sh` would have refused it. |
| 7 | benchmark run through a stale harness copy (instrument identity unchecked) ([#4436](https://github.com/melodic-software/claude-code-plugins/issues/4436)) | plausible numbers, run completed | The copy was nine commits behind origin and lacked the transcript-size arm and the process counter. Nothing errored. Caught only by a missing output column. |
| 8 | Stop-hook benchmark with stale path-selecting state ([#4437](https://github.com/melodic-software/claude-code-plugins/issues/4437)) | plausible numbers, run completed | A `bench.launched` marker left by an earlier run sent every sample down the rare Python path. The common skip path was never measured. Nothing errored. |

None of these are knowledge gaps. They are all "the measurement was wrong in a way that looked
right". A workflow that measures without enforcing the rules below mostly generates confident
numbers, which is worse than generating none.

## The rules

### 1. A harness must prove it is not measuring itself

Anything the harness injects into the environment under test (`PATH` entries, temp directories,
environment variables, working directory) is either **fixed across runs** or **provably irrelevant
to the subject's behavior**.

Failures 1, 3, and 4 in the table above share one root cause: the harness changed `PATH` in a way
that mattered to the subject.

Check it by running the harness twice against an **unchanged** subject. If the two runs disagree
beyond the host's characterized noise, the harness is a variable, not an instrument. A rig that
drives time in fixed ticks checks itself the same way: N ticks in must yield exactly N units out.

### 2. A probe must assert its own precondition

If a test depends on a hard link, a symlink, a particular filesystem, a permission, or a binary being
present, it must **FAIL when that precondition is unmet**. It must never silently degrade into a
weaker test that passes.

Failure 2 is the canonical shape: a `try: os.link / except: shutil.copyfile` fallback turns a
link-identity probe into a probe of something else, and reports success.

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

Point 3 is the one that catches failures 3, 4, and 5. Without it, a harness where both arms exit 127
reports a clean, confident, wrong verdict.

Assert that the patch changed something before running the arm. A patch that silently applied
nothing is arm 3's failure mode.

For a check that may be flaky (a race, a timing-dependent defect), one run per arm proves nothing.
Repeat each arm N times, with N chosen per check and recorded in the report, and require N/N in
both: the negative arm fails on every run and the positive arm passes on every run. An arm that
fails 9 of 10 runs is flaky, not failing.

### 4. Restore from saved bytes, not from version control

Take an in-memory or on-disk copy of the file **before** editing it, and restore from that copy.

`git checkout --` is correct only when the code under test is already committed, and is **actively
destructive** otherwise. That is failure 5: the restore reverts the uncommitted fix, and the work is
gone.

Verify the restore rather than assuming it: an empty `git diff` against the commit, or a byte
comparison against the saved copy. "I restored it" is not evidence.

### 5. Commit before you verify

This makes the restore path safe and makes an accidental clobber recoverable. It is the cheapest
mitigation for rule 4 and costs nothing.

### 6. Windows drive-letter paths are a first-class hazard

Path spelling is behind failures 3 and 4 in the table above, and path resolution behind failure 6.

- Windows path spellings are not interchangeable, and which ones break is verified rather than
  assumed. A drive-letter path in forward-slash form (`D:/...`) does resolve when bash itself reads
  it. The same path in backslash form (`D:\...`) collapses when it is interpolated unquoted into a
  command string, because bash consumes the backslashes, and the command then exits 127. Quoted,
  that same backslash path reads fine, so the hazard is the unquoted interpolation rather than the
  backslashes alone. Hand bash the POSIX form (`/d/...`) so neither spelling question arises. Both
  spelling claims in this bullet were verified 2026-09-06 on bash 5.3.15 under
  MINGW64_NT-10.0-26200; recheck when the host shell or the MSYS runtime changes.
- Windows `PATH` entries in drive-letter form break bash's colon-separated parsing, because the colon
  after the drive letter is read as a separator.
- `os.link` fails across volumes; `shutil.copyfile` does not, which is exactly what makes the
  fallback dangerous.
- **Resolution is a hazard as well as spelling.** A bare interpreter name (`bash`, `python3`)
  resolves by `PATH` order, and a mixed host can carry several candidates: `cmd /c where bash`
  returned four on the host behind failure 6, one of them WSL's launcher, and the Windows `PATH` a
  native `subprocess` searches is not the one the Bash tool's shell sees. Invoke every interpreter a
  harness spawns from its own code by absolute path. `harness_require_python` in
  `scripts/harness-lib.sh` pins the Python it finds by absolute path and runs it once before
  trusting it; `scripts/pathfix.py` converts a path to the spelling a native Windows Python needs.

On a mixed MSYS/native host this is not an edge case. It is the default hazard.

### 7. Instrument identity is verified, not assumed

A harness copy that is behind its source, or a different copy from the one that took the baseline,
produces numbers that look like measurements. Failure 7 completed with plausible values.

- Record the identity of every measuring tool before timing: resolved path, revision or content
  hash, and version when it reports one.
- Check that the copy is not behind its upstream, from local refs only (no fetch), and that the
  output column or field the goal's metric names is actually produced.
- A post snapshot repeats the baseline's identity line and flags any difference in path, revision
  or version. A before/after pair taken with two tool copies does not isolate the change, so its
  ratio is not reported.

### 8. A frozen harness prints its error and work counts

A harness frozen for repeated runs prints, on every run, how many operations failed and how many
units of work it completed. A change that makes the subject fail sooner or skip work lowers a
duration or a counter just as a real gain does; the two counts are what tell them apart. A run
whose error count rose, or whose work count differs from the baseline arm's, is not a gain.

## Process counting on MSYS/Cygwin (Git Bash)

**Claim:** On Git Bash under MSYS, many Windows-side process counters (Job Object child counts,
Process Explorer, some hook telemetry) rise by **two** per external command the shell runs.
**Basis:** The +2 was observed during Windows hook-latency work ([#4408](https://github.com/melodic-software/claude-code-plugins/issues/4408)); one added `tail` raised the job-object count by 2, not 1.
**As-of:** 2026-09-28. **Recheck:** when the host shell or MSYS runtime changes.

A likely explanation, not verified here, is one count for the MSYS fork and one for the Windows
`CreateProcess` the shim performs to run the real binary. Treat the mechanism as a hypothesis; the
observed +2 is the claim.

This plugin's spawn census counts **PATH-shim intercepts** (external tools the subject invoked),
not Job Object membership. A goal that expects "+1 process" from "+1 external command" on MSYS must
state which accounting it uses. The census line is labeled `spawns=` in `spawn-census.sh` output;
quote that label in the goal and snapshot report rather than re-labeling it as a Job Object delta.

**Zero-process cases** (do not expect a shim hit or a Job Object bump from these alone):

- shell **builtins** (`echo`, `cd`, `test`, …)
- **`$(<file)`** and other redirection forms that do not spawn a child to read the file

Expected counter delta per external command, by platform:

| Platform | Expected delta | Status |
|---|---|---|
| MSYS/Cygwin Git Bash | +2 | measured ([#4408](https://github.com/melodic-software/claude-code-plugins/issues/4408)) |
| POSIX shell on Linux or macOS | not measured by this plugin | unmeasured |
| Native Windows (`cmd`, PowerShell) | not measured by this plugin | unmeasured |

When the goal's counter is a Windows-side process count, record the expected **+2 per external
command** on MSYS in the goal's `Boundary:` or `Done when:` line, or prefer the bundled spawn census
so before/after comparisons use one accounting end to end.

## Two shell behaviors that hide a wrong number

- **`$(...)` command substitution is a process spawn on MSYS, even around builtins.** A
  "builtins-only" hot path that reports via stdout still costs a full process. A spawn-count harness that ignores its own
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
- [ ] A check that may be flaky ran each arm N times, N is recorded, and both arms were N/N.
- [ ] The code under test was committed before the check ran.
- [ ] Restores came from saved bytes, and the restore was verified.
- [ ] Every path handed to a shell is in that shell's own path form.
- [ ] Every interpreter a harness spawns from its own code (a `subprocess` call, a script) is
      invoked by absolute path, never by bare name.
- [ ] No sample exited 127 or 126. A timing that is fast and identical across every sample is
      failure 6's signature until the exit codes say otherwise.
- [ ] Instrument identity is verified: the measuring tool's path, revision and version were
      recorded, the copy is not behind its upstream, the goal's metric column is produced, and a
      post snapshot matches the baseline's recorded tool.
- [ ] State that selects the subject's code path was reset or recorded before each arm, and the
      observed path matches the goal's.
- [ ] The bundled harness in `scripts/` ran where one exists for the job (`ab.sh`,
      `run-spawn-census.sh`, `differential.py`, `discriminate.py`), rather than a reimplementation.
