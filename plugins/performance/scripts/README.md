# Measurement harnesses

The reference implementations `/performance:snapshot` and `/performance:verify` run. Read
[`../reference/harness-integrity.md`](../reference/harness-integrity.md) first: these scripts exist
to ENFORCE the rules in it, and every refusal below is a defect that shipped in the source run.

| Script | Owns |
|---|---|
| `harness-lib.sh` | Shared preconditions: drive-letter path refusal, shim-directory stability, the injected-PATH ledger, interpreter discovery. |
| `pathfix.py` | MSYS versus native-Windows path spelling, for the Python harnesses. |
| `spawn-census.sh` | One process-spawn census of one subject command, via a stable PATH shim directory. |
| `run-spawn-census.sh` | Before and after censuses, with the rule 1 warm-agreement proof. |
| `ab.sh` | Interleaved A/B timing with order flipping, order-flipped per iteration. |
| `summarize.py` | Per-arm p50 and p95, refusing any percentile the sample count cannot express. |
| `ratio.py` | Paired ratio, suppressed under concurrency. |
| `differential.py` | Pre-change versus post-change behavior over an argv matrix: byte-identical stdout and exit code, with any stderr difference disclosed as outside that bar. |
| `discriminate.py` | Does this check actually fail without the fix. |

Every script carries a co-located `<stem>.test.sh`. Run one with `bash <stem>.test.sh`.

## What these refuse to do

- **Invent a shim directory.** `--shim-dir` is required and a temporary root is rejected. The source
  census used `mktemp -d`, changed `PATH` every run, forced a permanent cache miss in a subject that
  cached keyed on `PATH`, and reported "no improvement" while measuring its own randomization.
- **Skip an unresolvable tool.** The source census did, which undercounts silently.
- **Fall back to `date(1)` for timing.** A process spawn per sample measures the instrument.
- **Report a percentile the sample count cannot express.** `p95` needs 20 samples; below that the
  printed value is the maximum wearing a percentile's name.
- **Report a headline paired ratio from a handful of pairs.** Two IDENTICAL arms measured here spread
  0.78x to 17.12x at five pairs, and once read 17.12x. The default floor is 20 pairs; below it the
  raw per-pair ratios are printed instead.
- **Pair samples that were not load-matched.** Concurrency suppresses the paired ratio outright.
- **Count a subject that never ran.** Exit 126 as well as 127: "found but not executable" produces
  the same tidy `spawns=0` line as "not found".
- **Time on a clock it cannot read.** A comma-decimal locale renders `EPOCHREALTIME` as
  `1788283754,274241`. That is refused by name rather than corrected, because changing the locale
  would change the environment the SUBJECT runs in. The refusal names the variable that actually
  governs: POSIX precedence is `LC_ALL` over `LC_NUMERIC` over `LANG`, so suggesting `LC_NUMERIC=C`
  while `LC_ALL` is set would be advice that silently does nothing.
- **Call two arms that both failed "parity" or "not discriminating".** Those are harness failures and
  are reported as such, with a distinct exit status. Two arms that both FAILED identically are
  indistinguishable from two arms that never ran, so that case is refused rather than scored; two
  arms that both PASSED are a knowable finding and are reported as a check that cannot fail.
- **Restore from `git checkout --`.** The pre-patch bytes go to a sidecar file first, the restore
  comes from that, and the restore is verified by byte comparison.

## The path hazard, in both directions

This is the trap that produced three of the five source-run failures, and it is not symmetric:

- **bash needs the MSYS spelling.** A `D:/...` path handed to bash resolves nowhere. The shell
  harnesses refuse one outright unless `--allow-windows-paths` is passed.
- **A native Windows interpreter needs the native spelling.** The `python3` on this kind of host is
  a native build, so `/d/worktrees/repo/x.py` resolves to `D:\d\worktrees\repo\x.py`, which is
  nowhere. `pathfix.py` resolves that, loudly.
- **MSYS rewrites argv, but not file contents.** A POSIX path on the command line of a native
  executable arrives already converted, so the same spelling works in argv and fails inside a JSON
  config. That asymmetry gets debugged in the wrong place.
- **`/tmp` and `/usr/bin` are MOUNTS**, with no drive letter to fold. Only `cygpath -w` knows the
  mount table, which is why `pathfix.py` asks it as a last resort.

`discriminate.py` deliberately does NOT rewrite `check.argv`: a bash check needs MSYS paths in its
arguments and a native check needs native ones, so rewriting would break whichever the caller meant.
Name the check relative to `check.cwd`, which the harness does resolve.

## Exit statuses

`0` the harness ran and the result is as expected. `1` the subject or the comparison came out
negative: a mismatch, a check that does not discriminate. `2` the harness could not run, or could not
have measured what it claims. The `1` and `2` split is load-bearing rather than tidy: conflating "the
check does not discriminate" with "the check never ran" is what produced four confident wrong
verdicts in the source run.
