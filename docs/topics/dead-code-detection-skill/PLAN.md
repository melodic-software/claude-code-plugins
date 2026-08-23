# dead-code-detection-skill

## Brief

> **Revision 4 (2026-08-23).** Three adversarial validation rounds (`/planning:audit-answers`,
> three fresh-context validators each). Round 3 validators installed and ran both detectors
> against purpose-built trap fixtures; revision 4 is written against those measurements, not
> against tool documentation. Material changes from revision 3: home returns to `code-tidying`
> (naming grammar + the `audit-comment-residue` precedent + intra-plugin routing needs no seam
> gate); the shell/grep lane is **un-deferred** because its stated trigger fired under
> measurement; knip's config evaluation is disclosed rather than denied; and four factually
> wrong specifications are corrected.

### Measured baseline (round-3 validators, this repository and hermetic fixtures)

These numbers are the design's evidence base. Any later change that contradicts them needs new
measurement, not argument.

| Claim | Measurement |
|---|---|
| vulture precision / recall on trap fixtures | **16.7% (3/18) / 100%** — all five trap classes false-positived at 100% |
| vulture confidence knob | **Does not exist for this skill's targets.** `--min-confidence 60` → 18 findings; `70`/`90`/`100` → **0**. Every unused function/class/method/variable/attribute is pinned at exactly 60; 100 is reserved for intra-function unreachable code |
| knip precision / recall on trap fixtures | **60% (3/5) / 100%** |
| knip config evaluation | A side effect planted in `knip.config.js` **fired** — knip evaluates repo-controlled config through `jiti`. The same experiment in Python **did not** fire: vulture is genuinely pure |
| knip `unresolved`/`unlisted` as a restore signal | **Refuted.** Restored vs unrestored JSON was byte-identical; these report source defects, not restore state |
| knip unrestored behavior | **Manufactures false positives** — a failed `vitest.config.ts` load produced 2 false "unused files"; the `ERROR:` line goes to **stderr**, which `--reporter json` discards |
| knip exit codes | `0` clean, `1` findings, **`1` hard error** — indistinguishable |
| vulture exit codes | `0` clean, **`3` findings**, `1` input error |
| knip class members | `--include classMembers` → `ERROR: Invalid issue type`. Absent from knip 6.32.2 entirely |
| shell/grep lane | **4/4 true positives, 0 false positives, 3.1s** over 546 `.sh` / 177,793 lines using the portable `grep -w -F -f` floor; shellcheck found **0** of the same 4 |
| `grep -w` precision | 8/12 probes. `$`, `-`, `.` are non-word characters → false-**alive**; `-F` is mandatory (without it `core.ts` matches `coreXts`) |
| Binary resolution | `npm i -D knip` → **not on PATH**; `uv add --dev vulture` → **not on PATH**. Bare-name probing reports "missing" on correctly-configured repos |

### TLDR

- New skill `code-tidying:audit-dead-code` — a whole-repo, cross-file dead-code hunter, the gap no existing skill covers.
- Three lanes with **honestly unequal** confidence: knip (TS/JS, 60% precision), vulture (Python, high-recall/low-precision), and a portable grep lane (shell and other symbol languages, high-precision/low-recall).
- Report-only to the human; no findings file, no relay, no suppression record in V1.
- Every candidate adjudicated against dynamic-usage evidence under a `--max` cap, oldest-untouched first.
- The skill's headline is a **TS/JS dead-code skill with a high-recall Python lane and a high-precision shell lane** — stated that way in the skill body, not implied as parity.

### Goal

Find dead code that nothing has touched in a long time — the category lane-rotated tidying and
diff-scoped simplification structurally cannot see. A run answers "what in this repository is no
longer reachable, and how confident are we?" with every candidate adjudicated against the
dynamic-usage patterns static analyzers are blind to, so the report is a list of decisions a human
can act on rather than a raw analyzer dump the reader must re-verify.

### Constraints

- **Report-only.** The skill never edits source and V1 writes no file. Findings are presented in-session.
- **No detector that builds the project or executes its application or test code.** This excludes
  Go, Rust, and .NET (measured: `cargo check` runs `build.rs`; `deadcode` needs a module graph and
  a `main` root). **knip is admitted with a disclosed exception**: it evaluates the repository's own
  config modules via `jiti`, and every run that loads a JS/TS config says so in the report. Denying
  this would be false; the exception is narrower than a build and is stated rather than hidden.
- **Never let a package runner fetch.** The rule is *never fetch*, not *never use a runner*:
  measured, `npx` on a locally-installed devDependency performs zero network I/O, while `npx` on an
  absent tool installs it. Detector invocation goes through the bundled script under one
  `Bash(${CLAUDE_SKILL_DIR}/scripts/dead-code-scan.sh:*)` grant.
- **"Resolvable local binary" is defined**, not assumed: PATH ∪ the repo-local `node_modules/.bin`
  walk (following symlinks with a hop cap, requiring the physical target to stay inside the repo's
  `node_modules`) ∪ `.venv/bin`. `plugins/markdown-format/hooks/markdown-format.sh:449-500` is the
  reference implementation and its ~60 lines are budgeted.
- **Presence is proven by invocation, never by `command -v`**, and **exit code is never read as run
  health** — the two detectors disagree about what each code means (see the baseline table).
- **Run health is parsed from stderr, not stdout or exit status.** Any knip `ERROR:` line makes the
  run DEGRADED. The restore state is probed **directly** (`node_modules` present and non-empty at
  the resolved root), never inferred from `unresolved`/`unlisted`.
- **Three run states, not two**: ran / skipped / degraded, plus **scanned-zero-files**, which both
  detectors otherwise report as exit 0 with no output — indistinguishable from clean.
- **Candidate scope and reference-search scope are separate.** A scoped run still searches
  references repo-wide.
- **No `## Pre-computed context` block.** The body invokes `scripts/dead-code-scan.sh` explicitly
  (`testing:audit`'s shape), keeping detector invocation off the auto-invocation path.
- **Portable reference search**: `grep -w -F` is the floor and `-F` is mandatory. A hit adjacent to
  `$`, `-`, or `.` requires model inspection rather than an automatic `alive`.
- **Pipeline safety**: vulture raises `BrokenPipeError` and returns 1 when its stdout closes early,
  so no detector output is piped into an early-closing reader under `set -o pipefail`.
- **Input filtering**: vulture handed a non-`.py` file emits a parse error **in exact finding
  format on stdout with exit 0**; globs are filtered to `*.py` and the parser rejects any line that
  is not `unused|unreachable|unsatisfiable`.

### Acceptance criteria

- `plugins/code-tidying/skills/audit-dead-code/` exists with `SKILL.md`, `scripts/dead-code-scan.sh`,
  `scripts/dead-code-scan.test.sh`, `scripts/lib/dead-code-shapes.sh`, `evals/evals.json`, and
  `evals/fixtures/`. `context/` spokes carry per-detector detail so `SKILL.md` stays near the
  200-line soft target.
- Three lanes ship, each labelled with its measured confidence character in the skill body:
  **knip** (TS/JS — unused files, exports, types, enum members; **not** class members, which knip 6
  rejects), **vulture** (Python — symbol-level), and **grep** (shell and other symbol languages —
  high precision, acknowledged low recall).
- Orphaned-file coverage is stated as **TS/JS only**.
- knip runs **per project root** (discovered via `package.json`), not once at the repo root; each
  root reports its own ran/skipped/degraded state.
- vulture ships with the FP-class suppressions that measurably work pre-applied
  (`--ignore-decorators`, `--ignore-names` for `test_*`/`pytest_*`), and the skill body states its
  measured precision floor rather than implying parity with knip.
- Every candidate carries one of exactly three verdicts — `dead`, `uncertain`, `alive` — and every
  `alive` cites the specific evidence that saved it.
- The adjudication pass is bounded: `--max <n>`, ordering by **git recency, oldest-untouched
  first** (the confidence key is inert — vulture pins everything at 60 and knip has no confidence
  field at all), an `n dropped by cap` line, and subagent fan-out with a stated inline fallback for
  spawn-depth exhaustion. The consent gate prints a **candidate count and the cap**, never a
  fabricated time or token figure.
- Repo lint-exclusion config is honored: `**/evals/fixtures/**` is excluded from scanning, matching
  the policy `ruff.toml` already establishes.
- Suppression entries are emitted as ready-to-paste text in each detector's native format, with the
  note that a committed vulture whitelist raises `F821` under a consumer's ruff config. The skill
  writes nothing. **SKILL.md states the convergence loop explicitly**: adjudicate → paste native
  suppressions → the next run is cleaner, and `dead`/`uncertain` verdicts are session-scoped.
- Eval fixtures include canned tool-output fixtures driving the **parsing** layer hermetically: a
  real knip `--reporter json` blob, a **degraded knip stderr capture** (the actual degradation
  signal, which the JSON fixture structurally cannot carry), a vulture text block, and a **vulture
  parse-error line** (indistinguishable from a finding by shape). All captures are taken with
  **cwd = repo root**, since vulture relativizes to cwd and a capture from elsewhere bakes in host
  paths. Adjudication is model judgment asserted in `evals.json`, which nothing in CI executes —
  stated as a limitation, not claimed away. Trap discrimination is asserted in
  `dead-code-scan.test.sh`. A read-only guardrail case asserts the skill declines to fix when asked.
- Beck #2 routing lands on **two** surfaces only — the new skill's `description` and
  `plugins/code-tidying/skills/tidy/reference/tidyings.md` #2. Intra-plugin, so no seam-phrasing
  gate is required. The four `templates/*-lane.template.md` files are **left alone**: they are
  scaffolded into consumer repos, where a pointer would be frozen at scaffold time with no update path.
- `dead-code-scan.test.sh` passes; `check-skill.sh --require-evals`, `check-evals-quality.sh`,
  `check-shell-portability.sh`, `check-orphaned-fixtures.sh --check`, and
  `check-changelog-parity.sh --check` all pass; both catalog generators are regenerated and clean.
- Registration: `code-tidying` plugin.json description + minor version bump, CHANGELOG entry, and a
  README roster that **repairs the existing "Three skills" staleness** — four skills are on disk
  today (`audit-comment-residue` was never added) and this makes five.

### Captured assumptions

- Ecosystem classification consumes `.claude/ecosystems/<eco>.yaml` `globs` where present and falls
  back to a small in-skill glob table otherwise (this repo has no `.claude/ecosystems/`, so the
  fallback is the common path). `install-hint` is **not** consumed — measured, it is one
  ecosystem-level string naming that ecosystem's lint tools (`ruff pyright uv`), never a detector.
- A shell fixture holding a dead *function* trips no CI check (measured: shellcheck finds none); a
  dead *variable* fixture would fire SC2034 and is avoided.
- Canned captures carry no host paths when taken with cwd = repo root — verify against the real
  capture before committing; the `machine-specific-paths` gate is a pinned external action whose
  internals could not be read.
- The `grep` lane's false-alive classes cause **missed** dead code, never condemned live code —
  acceptable for a read-only skill, and the reason the lane ships as high-precision/low-recall.

### Out-of-scope

- Go, Rust, and .NET detection. **Trigger:** a detector that neither builds nor executes project code.
- `--persist-findings`, the `review-findings` relay, and its crosswalk rows. **Trigger:** a fanout
  cleanup route that reads findings files — today it routes dead-code removal to `/simplify`, which
  "does NOT read the findings files".
- The `finding-suppression` record and a code-symbol anchor scheme. **Trigger:** V1 false-positive
  volume proving native per-tool suppression insufficient.
- `userConfig` knobs; detector policy is team policy and `userConfig` is explicitly not repository configuration.
- Unused dependencies, dead config keys, unreferenced assets, stale feature flags.
- Any source edit or deletion — permanently out of scope by design.
- Coverage-based (runtime) dead-code detection.

### Deferred questions

- Q13 — Should V2 add unused-dependency reporting first, given knip already emits it in the pass V1
  discards it from? — defer until V1 ships; **arbiter: USER-RESERVED**
- Q14 — Does a known-alive/entry-point config become necessary for reflection-heavy repositories? —
  defer until V1 false-positive rates are observed; **arbiter: USER-RESERVED**
- Q23 — Should the skill eventually offer quarantine/staged removal, given the `dead-code-sweep`
  routine class mandates a 30–90 day quarantine floor? — defer until a routine is built on this
  skill; **arbiter: USER-RESERVED**
- Q27 — `uncertain` has no exit path without persistence: it neither converges nor is remembered
  across runs. Should it be emitted inside the paste-ready suppression block, commented out with
  the open question, so the repo carries the memory while the skill still writes nothing? — defer
  until V1 shows how large the `uncertain` bucket actually is; **arbiter: USER-RESERVED**

## Plan

<!-- populated by /planning:plan -->
