---
description: "Hunt dead code across a whole repository through four labelled lanes of unequal confidence — knip (TS/JS unused files, exports, types, enum members), vulture (Python symbols), gopls (Go unexported symbols), and a portable grep lane (shell and other symbol languages) — then adjudicate every candidate against the dynamic-usage evidence static analyzers are blind to, emitting Tier 1 (dead) and Tier 2 (uncertain) findings plus paste-ready native suppressions; read-only, no edits applied. Use when: 'find dead code', 'audit dead code', 'what is unused in this repo', 'unused exports', 'unreferenced functions', 'orphaned files', 'is anything here still called', 'dead code sweep', or when long-untouched code needs a deliberate hunt a rotated tidying lane never reaches — not for applying the deletion or Beck's Dead Code tidying (use /code-tidying:tidy), diff-scoped simplification of recently changed files (use /code-tidying:batch-simplify), comment residue (use /code-tidying:audit-comment-residue), or unused dependencies, assets, and coverage-based runtime detection, which are out of scope."
argument-hint: "[--max N] [--lane knip|vulture|gopls|grep] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh:*)", "Bash(git grep:*)", "Bash(git log:*)", "Bash(grep:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Whole-repo dead-code hunt across four labelled lanes with adjudicated candidates
---

## Purpose

Find code nothing has touched in a long time — the category a rotated tidying lane and a
diff-scoped simplification pass structurally cannot see. A run answers *what in this repository is
no longer reachable, and how confident are we?* Every candidate is adjudicated against the
dynamic-usage patterns static analyzers are blind to, so the report is a list of decisions a human
can act on rather than an analyzer dump the reader must re-verify.

The headline is **four lanes of unequal strength, each labelled** — not four peer detectors. A
report that presents them as equals is wrong even when every finding in it is right.

## The four lanes are not peers

| Lane | Covers | Measured character | How it fails |
|---|---|---|---|
| **knip** | TS/JS: unused files, exports, types, enum members. **Not** class members — knip 6 rejects `--include classMembers` outright | **60% precision / 100% recall** on trap fixtures | Unrestored, it **manufactures false positives** (a failed config load produced 2 phantom "unused files"). Its `ERROR:` line goes to stderr, which the JSON reporter discards |
| **vulture** | Python: unused function / class / method / variable / attribute, plus unreachable code | **16.7% precision / 100% recall** — all five trap classes false-positived at 100% | High recall, low precision **by construction**. Read its output as a worklist, never as a verdict |
| **gopls** | Go: **unexported symbols only** (`gopls check -severity=hint`). That is the lane's declared coverage, not a defect | Correct on every measured symbol; 2.1s | An unresolved module graph **suppresses hints** — false **NEGATIVES**, the opposite of knip. Never describe the two degradations with one shared phrase |
| **grep** | Shell and other symbol languages: function definitions with no reference anywhere | **4/4 true positives, 0 false positives** over 546 `.sh` / 177,793 lines; shellcheck found 0 of the same 4 | High precision, **acknowledged low recall**. `$`, `-`, `.` are non-word characters, so an adjacent hit reads as a reference and quietly saves a symbol that may be dead |

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
findings — they are what makes a clean report a claim rather than an absence.

**Candidate scope and reference-search scope are separate.** A `target` narrows which files
*produce* candidates; the reference search stays repository-wide, because a reference from anywhere
still saves a symbol.

## Run states — four, not two

| State | Meaning |
|---|---|
| `ran` | the lane resolved a binary, invoked it, and read trustworthy output |
| `skipped` | no resolvable local binary, or a located binary that failed to invoke. Nothing was fetched — no package runner is ever called |
| `degraded` | the lane ran but its output is not trustworthy. **It emits no records**, and its line says why |
| `scanned-zero-files` | the lane had zero in-scope input files. Both detectors otherwise report this as exit 0 with no output — indistinguishable from clean |

A run where no lane reached `ran` is **a scan of nothing, not a clean bill**, and the script says so.

## Adjudication

Bounded by design. Full evidence catalogue in
[context/adjudication.md](context/adjudication.md) "Evidence patterns".

1. **Consent gate.** Report the candidate **count** and the `--max` cap from
   `Summary candidates:` and get a go-ahead before adjudicating. Never quote a time or token
   estimate — there is no measurement behind one.
2. **Order is git recency, oldest-untouched first.** The script already emits them that way. There
   is no confidence key to order by: vulture pins every symbol-level finding at exactly 60 and knip
   has no confidence field at all.
3. **Adjudicate each candidate to `dead`, `uncertain`, or `alive`**, checking the dynamic-usage
   patterns the detectors cannot see — string-name dispatch, DI/serialization, reflection, decorator
   and route registration, test-only entry points, public API surface, generated code.
4. **Every `alive` cites the specific evidence that saved it.** An unevidenced `alive` is a guess.
5. Fan out to fresh-context subagents in batches when the set is large; if spawn depth is
   exhausted, say so and adjudicate inline at the same cap rather than silently shrinking the set.
6. **Optional LSP assist**, never required and never a lane: when Claude Code's `LSP` tool is
   available, `findReferences` on one candidate is one more evidence source. `includeDeclaration` is
   hard-coded true, so the dead threshold is `resultCount == 1`. Imports count as references, so a
   re-export still reads alive.

## Hard rules

- **Read-only.** No `Edit`, no `Write`, no mutating `Bash`. The skill writes **no file** — not even
  a findings file. Every deletion is the human's.
- **Tier semantics.** The detector's tiers are candidate priors: T1 = high-confidence candidate,
  T2 = uncertain candidate, T3 = **detector drift** (output no parser recognized). In the
  adjudicated report the same tiers carry verdicts: `dead` → T1, `uncertain` → T2. **`alive` is
  never emitted as a record** — it is the adjudication saving a candidate, and emitting it would
  make `Summary total:` mean two different things at once.
- **T3 is the drift bucket.** An unrecognized detector line is recorded, never silently dropped and
  never counted as a finding. A fourth verdict would land here; that is the alarm, not the answer.
- **Exit codes are never run health.** knip exits 1 for findings *and* for hard errors; vulture
  exits 3 for findings, and 1 for a lone unparsable input; gopls always exits 0.
- **Presence is proven by invocation.** A locator hit is not a presence proof — measured,
  `command -v rust-analyzer` succeeds while invocation fails.
- **Never fetch.** Detectors run from a resolvable local binary (PATH, the repo-local
  `node_modules/.bin` walk, or `.venv/bin`) or the lane is `skipped`. No package runner is invoked.
- **knip evaluates repo-controlled config through jiti.** Disclosed on every run that loads one,
  never hidden. It is narrower than a build; vulture, measured, is genuinely pure.
- **`**/evals/fixtures/**` is never scanning input**, matching the policy `ruff.toml` already sets.
  A detector's planted-defect corpus is not the consumer's dead code.

## Output schema

The script emits flat records; the adjudicated report is what the human reads.

```text
Lane: knip | root=. | state=ran | files=231 | detail=285 candidate(s)
Note: knip evaluated knip.config.ts through jiti — a DISCLOSED exception ...
File: src/legacy/format.ts
Finding tier: 2
Finding shape: ts-unused-export
Finding line: 13
Finding excerpt: formatLegacyRow
---
Summary file: src/legacy/format.ts | T1=0 T2=1 T3=0
Summary lanes: ran=3 skipped=1 degraded=6 scanned-zero-files=2
Summary candidates: total=370 emitted=15 dropped-by-cap=355 cap=15
Summary total: files=15 T1=0 T2=15 T3=0
```

Present per file: verdict, shape, line, the evidence checked, and — for `alive` — what saved it.
Close with the lane roster, the candidate count against the cap, and `n dropped by cap`.

## Convergence loop

The skill writes nothing, so the memory has to live in the repository:

1. Adjudicate a bounded batch.
2. Paste the emitted suppression entries into each detector's **native** config — knip `ignore`
   entries, a vulture whitelist, a `//lint:ignore` directive. Formats in
   [context/adjudication.md](context/adjudication.md) "Suppression formats".
3. The next run is cleaner, and the batch after it reaches new code.

`dead` and `uncertain` verdicts are **session-scoped**: nothing persists them, so an un-suppressed
`uncertain` returns as a candidate on the next run. A committed vulture whitelist raises `F821`
under a consumer's ruff config — say so when you emit one.

## What this skill is NOT

- **Not `/code-tidying:tidy`.** `tidy` APPLIES Beck's Dead Code tidying inside one rotated lane;
  this hunts candidates across the whole repository and reports. Bring `dead` verdicts to `tidy`.
- **Not `/code-tidying:batch-simplify`.** That sweeps recently changed files; this deliberately
  targets the long-untouched ones a recency window excludes.
- **Not a dependency, asset, or feature-flag auditor**, and not coverage-based runtime detection.
- **Not an Edit operation.** It surfaces findings; the author applies every deletion.

## Gotchas

- **A `degraded` lane is not a quiet lane.** knip degraded means invented findings were withheld;
  gopls degraded means real findings were never produced. Report which one happened.
- **`grep -w -F` is the floor and `-F` is mandatory** — without it `core.ts` matches `coreXts`. A
  hit adjacent to `$`, `-`, or `.` needs model inspection; it is never an automatic `alive`.
- **knip runs per project root**, discovered via `package.json`, never once at the repo root. Each
  root carries its own state — one degraded workspace does not condemn the others.
- **vulture is handed only `*.py`.** Given anything else it logs a parse error to stderr and skips
  that file; that is an input note, not a degraded lane.
- **A cap can truncate a file's block.** `--max` counts candidates, not files, so `Summary file:`
  reflects what was emitted, not what exists.
