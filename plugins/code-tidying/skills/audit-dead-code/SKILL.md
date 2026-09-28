---
description: "Hunt dead code in four lanes (Knip, vulture, gopls, portable grep). Read-only. Use when: 'find dead code', 'audit dead code', 'what is unused in this repo', 'unused exports', 'unreferenced functions', 'orphaned files', 'is anything here still called', 'dead code sweep'. Not for applying the deletion (/code-tidying:tidy), diff-scoped simplification (/code-tidying:batch-simplify), or comment residue (/code-tidying:audit-comment-residue)."
argument-hint: "[--max N] [--lane knip|vulture|gopls|grep] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh:*)", "Bash(git grep:*)", "Bash(git log:*)", "Bash(grep:*)"]
metadata:
  workflow-stage: anytime
  summary: Whole-repo dead-code hunt across four labeled lanes with adjudicated candidates
---

## Purpose

Find code nothing has touched in a long time, the category a rotated tidying lane and a
diff-scoped simplification pass structurally cannot see. A run answers *what in this repository is
no longer reachable, and how confident are we?* Every candidate is adjudicated against the
dynamic-usage patterns static analyzers are blind to, so the report is a list of decisions a human
can act on rather than an analyzer dump the reader must re-verify.

The headline is **four lanes of unequal strength, each labeled**, not four peer detectors. A
report that presents them as equals is wrong even when every finding in it is right.

## The four lanes are not peers

| Lane | Covers | Measured character | How it fails |
|---|---|---|---|
| **knip** | TS/JS: unused files, exports, types, enum members. **Not** class members. Knip 6 rejects `--include classMembers` outright | **60% precision / 100% recall** on trap fixtures | Unrestored, it **manufactures false positives** (a failed config load produced 2 phantom "unused files"). Its `ERROR:` line goes to stderr, which the JSON reporter discards |
| **vulture** | Python: unused function / class / method / variable / attribute, plus unreachable code | **16.7% precision / 100% recall**. All five trap classes false-positived at 100% | High recall, low precision **by construction**. Read its output as a worklist, never as a verdict |
| **gopls** | Go: **unexported symbols only** (`gopls check -severity=hint`). That is the lane's declared coverage, not a defect | Correct on every measured symbol; 2.1s | An unresolved module graph **suppresses hints**. False **NEGATIVES**, the opposite of knip. Never describe the two degradations with one shared phrase |
| **grep** | Shell and PowerShell: function definitions with no reference anywhere | **4/4 true positives, 0 false positives** over 546 `.sh` / 177,793 lines; shellcheck found 0 of the same 4 | High precision, **acknowledged low recall**. `$`, `-`, `.` are non-word characters, so an adjacent hit reads as a reference and quietly saves a symbol that may be dead |

Every figure in the Measured character column comes from this plugin's own trap fixtures under
`evals/fixtures/`, as recorded on 2026-08-23. Recheck trigger: a major version bump in any lane's
detector, or a change to the fixture corpus. Re-measure before quoting one to a user.

Orphaned-**file** coverage is **TS/JS only**. Rust and .NET are permanently out of scope: their
detectors build the project. Per-lane invocation, flags, and degradation detail live in
[context/lanes.md](context/lanes.md) "Lane reference".

## Candidate shapes and default tiers

The detector emits **candidates**, not verdicts. A shape's tier is the candidate's prior, taken
from the measured precision of the lane that produced it.

| Shape | Lane | Default tier |
|---|---|---|
| `ts-unused-file` | knip | 2 |
| `ts-unused-export` | knip | 2 |
| `ts-unused-type` | knip | 2 |
| `ts-unused-enum-member` | knip | 2 |
| `py-unused-symbol` | vulture | 2 |
| `py-unreachable` | vulture | 1 |
| `go-unused-unexported` | gopls | 1 |
| `unreferenced-symbol` | grep | 1 |
| `detector-drift` | any | 3 |

Consumers with their own conventions can refine these defaults in their repo's `CLAUDE.md` /
rules; the tiers above are the skill's built-in baseline.

## Running the detector

```bash
${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh                      # whole repo, every lane
${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh --max 20             # cap the adjudication set
${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh --lane grep src/     # one lane, scoped candidates
${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh --help               # usage and exit codes
```

Exit is **0 on every scan path** and **2 only on a usage error**: a read-only audit never fails its
caller, and no detector's own exit code is ever propagated. Present the `Lane:` lines with the
findings. They are what makes a clean report a claim rather than an absence.

**Candidate scope and reference-search scope are separate.** A `target` narrows which files
*produce* candidates; the reference search stays repository-wide, because a reference from anywhere
still saves a symbol.

## Run states. Five, not two

| State | Meaning |
|---|---|
| `ran` | the lane resolved a binary, invoked it, and read trustworthy output |
| `skipped` | no resolvable local binary, or a located binary that failed to invoke. Nothing was fetched. No package runner is ever called |
| `degraded` | the lane ran but its output is not trustworthy. **It emits no records**, and its line says why |
| `scanned-zero-files` | the lane had zero in-scope input files it **owns** (a nested project root's files belong to that root). Both detectors otherwise report this as exit 0 with no output. Indistinguishable from clean |
| `no-manifest` | the lane's language is in scope, but no project manifest root exists (`package.json` for knip, `go.mod` for gopls). `files=` is the real in-scope count for that language. Those files are uncovered. This is not a missing binary |

`files=` on a `Lane:` line is the number of files that lane took as input, including `skipped` and `no-manifest`. It is not the number of findings.

A run where no lane reached `ran` and no source file is uncovered is **a scan of nothing, not a clean bill**, and the script says so. A run that leaves any in-scope source file uncovered is also not a clean bill, even when some lane ran. The clean-result note is printed only when `Summary coverage:` reports `uncovered=0`.

## Adjudication

Bounded by design. Full evidence catalogue in
[context/adjudication.md](context/adjudication.md) "Evidence patterns".

1. **Consent gate.** Report the candidate **count** and the `--max` cap from
   `Summary candidates:` and get a go-ahead before adjudicating. Never quote a time or token
   estimate. There is no measurement behind one. Done when the operator has explicitly approved
   adjudication or declined it (report-only).
2. **Order is git recency, oldest-untouched first.** The script already emits them that way. There
   is no confidence key to order by: vulture pins every symbol-level finding at exactly 60 and knip
   has no confidence field at all.
3. **Adjudicate each candidate to `dead`, `uncertain`, or `alive`**, checking the dynamic-usage
   patterns the detectors cannot see. String-name dispatch, DI/serialization, reflection, decorator
   and route registration, test-only entry points, public API surface, generated code.
4. **Every `alive` cites the specific evidence that saved it.** An unevidenced `alive` is a guess.
5. Fan out to fresh-context subagents in batches when the set is large; if spawn depth is
   exhausted, say so and adjudicate inline at the same cap rather than silently shrinking the set.
6. **Optional LSP assist**, never required and never a lane: when Claude Code's `LSP` tool is
   available, `findReferences` on one candidate is one more evidence source. `includeDeclaration` is
   hard-coded true, so the dead threshold is `resultCount == 1`. Imports count as references, so a
   re-export still reads alive. Done when every emitted candidate has a `dead`, `uncertain`, or
   `alive` verdict with evidence, or the cap stopped the batch and that stop is stated.

## Hard rules

- **Read-only.** No `Edit`, no `Write`, no mutating `Bash`. The skill writes **no file**, not even
  a findings file. Every deletion is the human's.
- **Tier semantics.** The detector's tiers are candidate priors: T1 = high-confidence candidate,
  T2 = uncertain candidate, T3 = **detector drift** (output no parser recognized). In the
  adjudicated report the same tiers carry verdicts: `dead` → T1, `uncertain` → T2. **`alive` is
  never emitted as a record**. It is the adjudication saving a candidate, and emitting it would
  make `Summary total:` mean two different things at once.
- **T3 is the drift bucket.** An unrecognized detector line is recorded, never silently dropped and
  never counted as a finding. A fourth verdict would land here; that is the alarm, not the answer.
- **Exit codes are never run health.** knip exits 1 for findings *and* for hard errors; vulture
  exits 3 for findings, and 1 for a lone unparsable input; gopls always exits 0.
- **Presence is proven by invocation.** A locator hit is not a presence proof. Measured,
  `command -v rust-analyzer` succeeds while invocation fails.
- **Never fetch.** Detectors run from a resolvable local binary (PATH, the repo-local
  `node_modules/.bin` walk, or `.venv/bin`) or the lane is `skipped`. No package runner is invoked.
- **knip evaluates repo-controlled config through jiti.** Disclosed on every run that loads one,
  never hidden. It is narrower than a build; vulture, measured, is genuinely pure.
- **`**/evals/fixtures/**` is never scanning input**, matching the policy `ruff.toml` already sets.
  A detector's planted-defect corpus is not the consumer's dead code.

## When coverage is incomplete

A `skipped` lane, a `scanned-zero-files` lane, or source files with no lane at all are gaps, not a
clean bill. After presenting the lane roster:

1. **Name each gap** from `Summary coverage:` and each `Note: uncovered` line: the path and the
   reason (`no lane for the language`, `no manifest root`, `tool not installed`, or `lane not
   selected`). Rust and .NET stay a policy exclusion: they are `no lane for the language`, not a
   detector this run forgot to invoke.
2. **Offer to file an issue** against this plugin with the file count and language, pre-filled for
   the operator to edit and submit. Do nothing unless they agree.
3. **Offer research and install**: with consent, run `/discovery:research` to pick a detector for the
   language, show the choice and its install command, and install or invoke it only after an
   explicit yes. Record its precision as **unmeasured** until trap fixtures cover it.

The default stays read-only: no package runner, no network fetch, and no build without consent
(#4524). Consent-gated lanes that may compile or execute project code remain out of scope here.

## Output schema

The script emits flat records; the adjudicated report is what the human reads.

```text
Lane: knip | root=. | state=ran | files=19 | detail=19 candidate(s); 269 finding(s) this root does not own dropped ...
Note: knip evaluated knip.config.ts through jiti — a DISCLOSED exception ...
File: src/legacy/format.ts
Finding tier: 2
Finding shape: ts-unused-export
Finding line: 13
Finding excerpt: formatLegacyRow
---
Summary file: src/legacy/format.ts | T1=0 T2=1 T3=0
Summary lanes: ran=3 skipped=1 degraded=6 scanned-zero-files=2 no-manifest=0
Summary coverage: covered=19 uncovered=2
Summary candidates: total=370 emitted=15 dropped-by-cap=355 cap=15
Summary total: files-with-findings=15 T1=0 T2=15 T3=0
Note: uncovered scripts/standalone.mjs — no manifest root
Note: uncovered src/main.rs — no lane for the language
```

`Summary total: files-with-findings=` counts files that emitted at least one candidate. `Summary coverage:` counts every in-scope source file: covered by a lane in `ran` or `degraded`, or uncovered. Uncovered reasons are `no lane for the language`, `no manifest root`, `tool not installed`, and `lane not selected`. Markdown, JSON, YAML, and other non-source files are not in that total. When `uncovered` is greater than zero the script lists each file and does not print the clean-result note or the scan-of-nothing note.

Present per file: verdict, shape, line, the evidence checked, and for `alive` what saved it.
Close with the lane roster, the candidate count against the cap, and `n dropped by cap`.

## Convergence loop

The skill writes nothing, so the memory has to live in the repository:

1. Adjudicate a bounded batch. Done when the batch is adjudicated or explicitly deferred.
2. Paste the emitted suppression entries into each detector's **native** config. Knip `ignore`
   entries, a vulture whitelist. Formats in [context/adjudication.md](context/adjudication.md)
   "Suppression formats". Done when the operator has the suppression text or has declined to apply it.
3. The next run is cleaner, and the batch after it reaches new code. Done when a follow-up scan is
   scheduled or the operator stops after one batch.

Only the knip and vulture lanes converge. **The Go and shell lanes have no native suppression**: measured, `gopls check -severity=hint` reports through every candidate directive (`//lint:ignore` is
staticcheck's and is not honored), so those verdicts live in the report and in a comment at the
declaration, and the same candidates return. Say so rather than emitting a directive that does
nothing.

`dead` and `uncertain` verdicts are **session-scoped**: nothing persists them, so an un-suppressed
`uncertain` returns as a candidate on the next run. A committed vulture whitelist raises `F821`
under a consumer's ruff config. Say so when you emit one.

## What this skill is NOT

- **Not `/code-tidying:tidy`.** `tidy` APPLIES Beck's Dead Code tidying inside one rotated lane;
  this hunts candidates across the whole repository and reports. Bring `dead` verdicts to `tidy`.
- **Not `/code-tidying:batch-simplify`.** That sweeps recently changed files; this deliberately
  targets the long-untouched ones a recency window excludes.
- **Not a dependency, asset, or feature-flag auditor**, and not coverage-based runtime detection.

## Next

`/code-tidying:tidy`

Adjudicated `dead` verdicts are applied there. This skill only reports.

## Gotchas

- **No `package.json` means knip does not scan `.js`/`.mjs`/`.cjs`.** Those extensions are routed to
  knip. With no manifest root the lane is `no-manifest`, `files=` is the real count, and each file
  is listed uncovered (`no manifest root`). The lane still emits no dead-code candidates for them.
  A file that sits outside every `package.json` root is uncovered the same way, even when some other
  root ran. A grep-lane fallback or knip-without-manifest scan for those files is **deferred**
  ([#4522](https://github.com/melodic-software/claude-code-plugins/issues/4522)).
  **Claim:** dead JS/TS outside any `package.json` root has no detector that emits candidates until
  trap-measured extractors ship. Coverage accounting lists the files; it does not scan them.
  **Basis:** #4522 and #4521. **As of:** 2026-09-28.
  **Recheck:** standalone `.mjs` trap fixtures produce candidates at recorded precision, or #4522
  unpark.
- **A `degraded` lane is not a quiet lane.** knip degraded means invented findings were withheld;
  gopls degraded means real findings were never produced. Report which one happened.
- **`grep -w -F` is the floor and `-F` is mandatory**, without it `core.ts` matches `coreXts`. A
  hit adjacent to `$`, `-`, or `.` needs model inspection; it is never an automatic `alive`.
- **knip runs per project root**, discovered via `package.json`. One run per root, never one run
  for the whole repository. Each root carries its own state, and each root reports only the files it
  **owns**: paths under it and under no nested root. A nested workspace's file is reported by that
  workspace's own run and only when that run is healthy, so one degraded workspace neither condemns
  the others nor has its withheld findings re-manufactured by an outer root's run.
- **vulture is handed only `*.py`.** Given anything else it logs a parse error to stderr and skips
  that file; that is an input note, not a degraded lane.
- **A cap can truncate a file's block.** `--max` counts candidates, not files, so `Summary file:`
  reflects what was emitted, not what exists.
