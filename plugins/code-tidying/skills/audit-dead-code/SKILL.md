---
description: "Read-only hunt for dead and unused code across four labeled lanes (Knip for TS/JS, vulture for Python, gopls for Go, grep for shell and files no lane owns), each candidate adjudicated dead, uncertain or alive. Use when asked to 'find dead code', to find what is unused in a repository (exports, functions, orphaned files), or whether anything still calls a symbol. Deleting what it finds is /code-tidying:tidy."
argument-hint: "[--max N] [--lane knip|vulture|gopls|grep] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh:*)", "Bash(git grep:*)", "Bash(git log:*)", "Bash(grep:*)"]
metadata:
  workflow-stage: anytime
  summary: Whole-repo dead-code hunt across four labeled lanes with adjudicated candidates
---

## Purpose

Find code nothing has touched in a long time, which a rotated tidying lane and a diff-scoped
simplification pass cannot see, and answer *what here is no longer reachable, and how confident are
we?* Every candidate is adjudicated against the dynamic-usage patterns static analyzers miss, so the
report is a list of decisions a human can act on, not an analyzer dump to re-verify.

## The four lanes are not peers

Present them as four lanes of unequal strength, each labeled. A report that treats them as equals
is wrong even when every finding in it is right.

| Lane | Covers | Measured character | How it fails |
|---|---|---|---|
| **knip** | TS/JS: unused files, exports, types, enum members. **Not** class members (Knip 6 rejects `--include classMembers`) | **60% precision / 100% recall** on trap fixtures | Unrestored, it **manufactures false positives** (a failed config load produced 2 phantom "unused files"); its `ERROR:` line goes to stderr, which the JSON reporter discards |
| **vulture** | Python: unused function, class, method, variable, attribute, plus unreachable code | **16.7% precision / 100% recall**; all five trap classes false-positived at 100% | Low precision by construction. Its output is a worklist, never a verdict |
| **gopls** | Go: **unexported symbols only** (`gopls check -severity=hint`), the lane's declared coverage | Correct on every measured symbol; 2.1s | An unresolved module graph **suppresses hints**: false **negatives**, the opposite of knip. Never describe the two degradations with one phrase |
| **grep** | Shell and PowerShell functions; `function`/`class`/`const`/`let`/`var` declarations in JS/TS no `package.json` root owns (`ts-unreferenced-symbol`); unreferenced source files (`unreferenced-file`) | Shell symbols: **4/4 true positives, 0 false** over 546 `.sh` files (shellcheck found 0 of the 4). JS/TS symbols: **66.7% precision / 66.7% recall** (as recorded 2026-09-29). `unreferenced-file` precision unmeasured | Low recall: `$`, `-`, `.` are non-word characters, so an adjacent hit reads as a reference and saves a possibly dead symbol. A JS/TS export only an entry point or outside consumer calls is a false candidate; a name in a comment saves a dead one |

Every figure comes from this plugin's trap fixtures under `evals/fixtures/`, as recorded on
2026-08-23 (JS/TS symbol figures 2026-09-29). Recheck trigger: a major version bump in any lane's
detector, or a change to the fixture corpus. Re-measure before quoting one to a user.

**Orphaned files.** The grep lane emits `unreferenced-file` (tier 2) for a source file no other
tracked file names, including languages with no lane, Rust and .NET among them. A reference in a CI
workflow, settings file, manifest or doc saves the file; a computed path or glob does not, so the
candidate is **uncertain, not dead**. Its input set, the no-lane extension list, per-lane
invocation, coverage accounting and degradation detail: [context/lanes.md](context/lanes.md)
"Lane reference".

## Candidate shapes and default tiers

The detector emits **candidates**, not verdicts. A shape's tier is its prior, taken from the
measured precision of the lane that produced it.

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
| `ts-unreferenced-symbol` | grep | 2 |
| `unreferenced-file` | grep | 2 |
| `detector-drift` | any | 3 |

`ts-unreferenced-symbol` is tier 2, unlike the shell `unreferenced-symbol`, because its measured
precision is 2 of 3 and an entry point or public export nothing in the repository calls reads as
unreferenced. A consumer's own `CLAUDE.md` or rules may refine these defaults.

## Running the detector

```bash
${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh                      # whole repo, every lane
${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh --max 20             # cap the adjudication set
${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh --lane grep src/     # one lane, scoped candidates
${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh --help               # usage and exit codes
```

Exit is 0 on every scan path and 2 only on a usage error; no detector's exit code is propagated.
Present the `Lane:` lines with the findings: they make a clean report a claim rather than an
absence. A `target` narrows which files *produce* candidates; the reference search stays
repository-wide, because a reference from anywhere saves a symbol.

## Run states. Five, not two

| State | Meaning |
|---|---|
| `ran` | the lane resolved a binary, invoked it, and read trustworthy output |
| `skipped` | no resolvable local binary, or a located binary that failed to invoke. Nothing was fetched; no package runner is ever called |
| `degraded` | the lane ran but its output is not trustworthy. **It emits no records**, its line says why, and its files are uncovered (`lane degraded`) |
| `scanned-zero-files` | the lane had zero in-scope input files it **owns** (a nested project root's files belong to that root). Indistinguishable from clean in the detectors' own output |
| `no-manifest` | the lane's language is in scope but no manifest root exists (`package.json` for knip, `go.mod` for gopls). Those files are uncovered unless another lane took them (grep takes JS/TS no `package.json` root owns). Not a missing binary |

`files=` on a `Lane:` line is the number of files that lane took as input, including `skipped` and
`no-manifest`; it is not the number of findings.

A run where no lane reached `ran` and no source file is uncovered is **a scan of nothing, not a
clean bill**, and the script says so. A run that leaves any in-scope source file uncovered, even
with some lane `ran`, is not a clean bill either: the clean-result note prints only when
`Summary coverage:` reports `uncovered=0`.

## Adjudication

Bounded by design. Evidence catalogue: [context/adjudication.md](context/adjudication.md)
"Evidence patterns".

1. **Consent gate.** Report the candidate count and the `--max` cap from `Summary candidates:` and
   get a go-ahead before adjudicating. Never quote a time or token estimate; there is no
   measurement behind one. Done when the operator has explicitly approved adjudication or declined it
   (report-only).
2. **Order is git recency, oldest-untouched first**, as the script emits them. There is no
   confidence key: vulture pins every symbol-level finding at 60 and knip has none.
3. **Adjudicate each candidate to `dead`, `uncertain`, or `alive`** against the dynamic-usage
   patterns detectors cannot see: string-name dispatch, DI and serialization, reflection, decorator
   and route registration, test-only entry points, public API surface, generated code. An
   `unreferenced-file` a computed path or glob could load is `uncertain`, not `dead`.
4. **Every `alive` cites the evidence that saved it.** An unevidenced `alive` is a guess.
5. Fan out to fresh-context subagents in batches when the set is large; if spawn depth is
   exhausted, say so and adjudicate inline at the same cap rather than silently shrinking the set.
6. **Optional LSP assist**, never required and never a lane: when Claude Code's `LSP` tool is
   available, `findReferences` on one candidate is one more evidence source. `includeDeclaration`
   is hard-coded true, so the dead threshold is `resultCount == 1`; imports count as references,
   so a re-export still reads alive. Done when every emitted candidate has a `dead`, `uncertain`
   or `alive` verdict with evidence, or the cap stopped the batch and the report says so.

## Hard rules

- **Read-only and never fetch.** No `Edit`, no `Write`, no mutating Bash, and no file written, not
  even a findings file; every deletion is the human's. Detectors run only from a resolvable local
  binary (PATH, the repo-local `node_modules/.bin` walk, or `.venv/bin`) or the lane is `skipped`;
  the script invokes no package runner. The one exception is installing or fetching a detector,
  only through "When coverage is incomplete" step 3, after an explicit yes.
- **Tiers.** Detector tiers are candidate priors: T1 high-confidence, T2 uncertain, T3 **detector
  drift** (output no parser recognized). In the adjudicated report `dead` → T1 and `uncertain` →
  T2. **`alive` is never emitted as a record**: it is a saved candidate, and emitting it would make
  `Summary total:` mean two things.
- **T3 is the drift bucket.** An unrecognized detector line is recorded, never dropped and never
  counted as a finding. A fourth verdict landing there is the alarm, not the answer.
- **Exit codes are never run health.** knip exits 1 for findings and for hard errors; vulture
  exits 3 for findings and 1 for a lone unparsable input; gopls always exits 0.
- **Presence is proven by invocation**, never by a locator hit (measured: `command -v
  rust-analyzer` succeeds while invocation fails).
- **knip evaluates repo-controlled config through jiti.** Disclose it on every run that loads one.
  It is narrower than a build, which is why the lane accepts it; vulture, measured, is pure.
- **`**/evals/fixtures/**` is never scanning input**, matching `ruff.toml`: a detector's
  planted-defect corpus is not the consumer's dead code.

## When coverage is incomplete

A `skipped`, `degraded`, `no-manifest` or `scanned-zero-files` lane, or source files with no lane,
are gaps, not a clean bill. After presenting the lane roster:

1. **Name each gap** from `Summary coverage:` and each `Note: uncovered` line: the path and the
   reason (`no lane for the language`, `no manifest root`, `tool not installed`, `lane degraded`,
   `tool could not parse it`, or `lane not selected`). Rust and .NET are a policy exclusion (`no
   lane for the language`), not a forgotten detector.
2. **Offer to file an issue** against this plugin with the file count and language, pre-filled for
   the operator to edit and submit. Do nothing unless they agree.
3. **Offer research and install**: with consent, run `/discovery:research` to pick a detector for
   the language, show the choice and its install command, and install or invoke it only after an
   explicit yes. Record its precision as **unmeasured** until trap fixtures cover it.

Consent-gated lanes that may compile or execute project code remain out of scope.

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
Summary lanes: ran=3 skipped=1 degraded=0 scanned-zero-files=2 no-manifest=0
Summary coverage: covered=19 uncovered=2
Summary candidates: total=370 emitted=15 dropped-by-cap=355 cap=15
Summary total: files-with-findings=15 T1=0 T2=15 T3=0
Note: uncovered cmd/tool/main.go — no manifest root
Note: uncovered src/main.rs — no lane for the language
```

`files-with-findings=` counts files that emitted at least one candidate. `Summary coverage:`
counts every in-scope source file as covered by a lane in `ran`, or uncovered with one of the
reasons above; markdown, JSON, YAML and other non-source files are not in it. The grep lane covers
files with no symbol lane, so `no lane for the language` remains only when that lane is not
selected.

Present per file: verdict, shape, line, the evidence checked, and for `alive` what saved it. Close
with the lane roster, the candidate count against the cap, and `n dropped by cap`.

## Convergence loop

The skill writes nothing, so the memory lives in the repository: adjudicate a bounded batch, hand
the operator suppression entries for each detector's **native** config (Knip `ignore` entries, a
vulture whitelist; formats in [context/adjudication.md](context/adjudication.md) "Suppression
formats"), and the next run reaches new code. Each step is done when the operator has the batch's
verdicts and suppression text, has declined them, or the batch is explicitly deferred; the loop ends when a follow-up scan is
scheduled or the operator stops after one batch.

Only knip and vulture converge. **Go and shell have no native suppression** (measured: `gopls
check -severity=hint` reports through every candidate directive; `//lint:ignore` is staticcheck's),
so those verdicts live in the report and in a comment at the declaration, and the same candidates
return. Say so rather than emitting a directive that does nothing.

`dead` and `uncertain` verdicts are session-scoped: an un-suppressed `uncertain` returns next run.
A committed vulture whitelist raises `F821` under a consumer's ruff config; say so when you emit
one.

## Boundaries

- `/code-tidying:tidy` applies Beck's Dead Code tidying inside one rotated lane; this hunts the
  whole repository and reports.
- `/code-tidying:batch-simplify` sweeps recently changed files; this targets the long-untouched
  ones a recency window excludes.
- Comment residue is `/code-tidying:audit-comment-residue`.
- Not a dependency, asset, or feature-flag auditor, and not coverage-based runtime detection.

## Next

`/code-tidying:tidy`

Adjudicated `dead` verdicts are applied there. This skill only reports.

## Gotchas

- **No `package.json` means knip scans no `.js`/`.mjs`/`.cjs`.** Its lane is `no-manifest` with
  the real file count, and the grep lane takes those files, and any JS/TS outside every
  `package.json` root, for `ts-unreferenced-symbol` and `unreferenced-file`. A symbol used only
  inside its own file counts as referenced.
- **A `degraded` lane is not a quiet lane.** knip degraded means invented findings were withheld;
  gopls degraded means real findings were never produced. Report which. Either way its files are
  listed uncovered, so the clean-result note cannot print.
- **A grep hit adjacent to `$`, `-`, or `.` needs inspection**; it is never an automatic `alive`.
- **knip runs once per `package.json` root**, and each root reports only the files it owns, so one
  degraded workspace neither condemns the others nor has its withheld findings re-manufactured by an
  outer root's run.
- **vulture is handed only `*.py`.** A parse error on another file is an input note, not a
  degraded lane.
- **`--max` counts candidates, not files**, so a cap can truncate a file's block: `Summary file:`
  reflects what was emitted, not what exists.
