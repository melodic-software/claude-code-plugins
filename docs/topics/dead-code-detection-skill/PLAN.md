# dead-code-detection-skill

## Brief

> **Revision 3 (2026-08-23).** Two adversarial validation rounds (`/planning:audit-answers`,
> three fresh-context validators each). Round 1 challenged all twelve revision-1 decisions;
> round 2 challenged eleven of fourteen revision-2 decisions and reclassified two to the human.
> Revision 3 is a deliberate **reduction**: revision 2 was more conformant and less buildable
> (budgeted at 2,450–3,400 lines — roughly three skills), and on a fully-provisioned machine its
> default run produced **zero** tool-backed findings. What survived round 2 unchallenged is kept;
> everything that could not be built or verified in V1 is deferred with a named trigger.
>
> Material changes from revision 2: home is `toolchain`, not `codebase-health`; the ecosystem
> roster is knip + vulture only; the `review-findings` relay, `--persist-findings`, the
> `finding-suppression` record, and `userConfig` are all deferred; the skill adopts
> `testing:audit`'s shape (no precompute block, an explicit script invoked from the body).

### TLDR

- New skill `toolchain:audit-dead-code` — a whole-repo, cross-file dead-code hunter, the gap no existing skill covers.
- V1 ships two detectors and only two: **knip** (TS/JS) and **vulture** (Python) — the only two in the surveyed field that are pure analysis, requiring no build and executing no project code.
- Report-only, to the human, with three verdicts (`dead` / `uncertain` / `alive`); no findings file, no relay, no suppression record in V1.
- Every candidate is adjudicated against dynamic-usage evidence under a `--max` cap, via subagent fan-out.
- Go, Rust, .NET, shell, persistence, and the relay are deferred — each with the trigger that would bring it back.

### Goal

Give the marketplace a way to find dead code that nothing has touched in a long time — the
category that lane-rotated tidying and diff-scoped simplification structurally cannot see. A run
answers "what in this repository is no longer reachable, and how confident are we?" with each
candidate adjudicated against the dynamic-usage patterns static analyzers are blind to, so the
report is a list of decisions a human can act on rather than a raw analyzer dump the reader must
re-verify.

### Constraints

- **Report-only.** The skill never edits source, and V1 writes no file at all. Every finding is
  presented to the human in the session.
- **Read-only means the process too, not just the source tree.** No detector that builds,
  restores, or executes project code ships in V1. This is what excludes Go, Rust, and .NET
  (measured: `cargo check` emits `"reason":"build-script-executed"` and runs the project's
  `build.rs`; `deadcode` requires a resolvable module graph and a `main` root).
- **Never auto-install tooling, and never invoke through a package runner.** `npx knip` downloads
  the package — an auto-install by another name — and `permission-rule-hygiene` records that
  package-runner grants are inert under auto mode, which is the default. Presence means a
  resolvable local binary.
- **Detector presence is proven by invocation, not by `command -v`.** `liveness-assertion` names
  "healthy-while-dead" as the defect where only configuration or process presence was checked.
- **Exit code is never read as run health.** Measured: knip and shellcheck both exit 1 when they
  find issues.
- **A partial sweep must never read as a complete one.** Each ecosystem reports ran / skipped /
  **degraded**, degraded being distinct from "no findings". A run where no detector resolved must
  not present as clean.
- **Candidate scope and reference-search scope are separate.** A scoped run still searches
  references repo-wide; otherwise every symbol defined inside the scope and used outside it is a
  false `dead`.
- **No `## Pre-computed context` block.** V1 follows `testing:audit`'s shape: the body invokes
  `scripts/dead-code-scan.sh` explicitly. This keeps detector invocation off the every-invocation
  path (including model auto-invocation) and gives the parsing layer a testable home.
- **Word-boundary reference search must be portable.** `\b`, `\<`, `\>`, `\w`, and `grep -P` are
  banned by `shell-portability-tokens.txt` in both `.sh` and skill markdown; `grep -w` is the floor.
- **Owned conventions bind**: `ecosystem-commands` (the consumer-declared `globs` / `install-hint`
  seam — consumed, not re-baked), `permission-rule-hygiene`, `liveness-assertion`, `seam-phrasing`
  (any cross-plugin pointer carries an installed-ness gate and a fallback), and the `audit` verb contract.

### Acceptance criteria

- `plugins/toolchain/skills/audit-dead-code/` exists with `SKILL.md`, `scripts/dead-code-scan.sh`,
  `scripts/dead-code-scan.test.sh`, a `scripts/lib/` shapes file, `evals/evals.json`, and
  `evals/fixtures/`. `context/` spokes carry per-detector detail so `SKILL.md` stays near the
  200-line soft target.
- Exactly two detectors ship: **knip** (TS/JS — unused files, exports, class/enum members) and
  **vulture** (Python — unused functions, classes, methods, variables, attributes, imports).
  Both are invoked as resolvable local binaries.
- Ecosystem classification consumes `.claude/ecosystems/<eco>.yaml` `globs` where present, and
  `install-hint` supplies the install line for a missing detector. No per-ecosystem table is baked
  into the skill.
- Orphaned-file coverage is stated as **TS/JS only** (knip is the sole detector in the field that
  reports unused *files*); Python coverage is symbol-level.
- Each detector's precondition is proven by a real invocation and reported: knip additionally
  requires a completed `node_modules` restore, and an unrestored run is **degraded**, not clean —
  knip's `unresolved`/`unlisted` categories are excluded as findings but retained as run-health signals.
- Every candidate carries one of exactly three verdicts — `dead`, `uncertain`, `alive` — and every
  `alive` cites the specific evidence that saved it.
- Suppression entries are emitted as ready-to-paste text in each detector's native format (knip
  `ignore` / `@public`; vulture `--ignore-names` / whitelist module). The skill writes nothing.
- The adjudication pass is bounded: a `--max <n>` cap, a **deterministic candidate order**
  (detector confidence, then repo-relative path, then symbol) so a capped run is reproducible, an
  `n dropped by cap` line in the summary, and subagent fan-out with a stated inline fallback for
  when spawn depth is exhausted. The consent gate prints a **candidate count and the cap** — not a
  fabricated wall-clock or token figure, for which V1 has no calibration source.
- `toolchain:setup check` reports detector presence and the install line for each missing detector.
- Eval fixtures include **canned tool-output fixtures** — a real knip `--reporter json` blob and a
  real vulture text block — driving the **parsing** layer hermetically in CI. Adjudication is model
  judgment and is asserted in `evals.json`, which nothing in CI executes; that limitation is stated
  rather than claimed away. Paired dead-symbol/dynamic-trap discrimination is asserted in
  `dead-code-scan.test.sh`. A read-only guardrail case asserts the skill declines to fix when asked.
- The skill's description routes explicitly against `/code-tidying:tidy` Beck #2, with a
  seam-phrasing gate and fallback; `tidyings.md` #2 points back. The boundary is also stated in the
  six further Beck-#2 sites (`lanes/shell-tooling.md`, four lane templates, `reference/scope-budget.md`).
- `dead-code-scan.test.sh` passes; `check-skill.sh --require-evals`, `check-evals-quality.sh`,
  `check-shell-portability.sh`, `check-orphaned-fixtures.sh --check`, and
  `check-changelog-parity.sh --check` all pass; both catalog generators are regenerated and clean.
- Registration is complete for `toolchain`: plugin.json description + minor version bump, README
  roster bullet and count, its "Three skills, one concern" framing widened to admit an audit skill,
  CHANGELOG entry, and both catalogs regenerated. Separately: `code-tidying`'s stale "Three skills"
  README roster (missing `audit-comment-residue`, four on disk) is repaired, and its
  `tidyings.md` edit carries its own version bump and CHANGELOG entry.

### Captured assumptions

- knip and vulture are the only two detectors in the surveyed field that require neither a build
  nor project-code execution — revisit if a comparable pure-analysis detector appears for another
  ecosystem.
- A shell fixture holding a genuinely-dead *function* trips no CI check (measured: shellcheck finds
  none), so no CI exemption is needed for the fixture set — revisit if a dead-*variable* fixture is
  added, which would fire SC2034 under the repo's unconditional whole-repo shellcheck step.
- Canned tool-output fixtures carry no absolute host paths and so will not trip the
  `machine-specific-paths` CI gate — verify against a real capture before committing; the gate is a
  pinned external action whose internals could not be read.
- Recorded fixtures stay valid across detector versions; each fixture records the tool version it
  was captured from — revisit when a detector's output schema changes.

### Out-of-scope

- Go, Rust, and .NET detection. **Trigger to revisit:** a pure-analysis detector that neither
  builds nor executes project code, or an explicit opt-in build lane accepted as a separate decision.
- A shell/"everything else" grep lane. **Trigger:** V1 false-positive data showing the grep lane's
  precision is acceptable under a portable `grep -w` search (the 0.3s/4-findings measurement used
  ripgrep and `-w`, which no plugin script currently uses).
- `--persist-findings`, the `review-findings` relay, and the severity-crosswalk rows it requires.
  **Trigger:** a fanout cleanup route that reads findings files — today it routes dead-code removal
  to `/simplify`, which "does NOT read the findings files".
- The `finding-suppression` record and the code-symbol anchor scheme it would need.
  **Trigger:** V1 false-positive volume proving native per-tool suppression insufficient.
- `userConfig` knobs. Detector policy is team policy, and `userConfig` is explicitly not repository
  configuration; V1 takes flags instead.
- Unused dependencies, dead config keys, unreferenced assets, stale feature flags.
- Any source edit or deletion — permanently out of scope for this skill by design.
- Coverage-based (runtime) dead-code detection — "unexecuted" is not "unreachable".

### Deferred questions

- Q13 — Should V2 add unused-dependency reporting first, given knip already emits it in the same
  pass V1 discards it from? — defer until V1 ships; **arbiter: USER-RESERVED**
- Q14 — Does a known-alive/entry-point config become necessary for reflection-heavy repositories? —
  defer until V1 false-positive rates are observed; **arbiter: USER-RESERVED**
- Q23 — Should the skill eventually offer quarantine/staged removal, given the `dead-code-sweep`
  routine class mandates a 30–90 day quarantine floor no delegation path provides? — defer until a
  routine is built on this skill; **arbiter: USER-RESERVED**
- Q26 — Does `toolchain`'s "mechanical verification of changed code" concern statement need a
  broader rewrite than a roster bullet, now that it hosts a whole-repo audit? — defer to the
  registration pass, where the exact wording is decided against the plugin's other skills;
  **arbiter: USER-RESERVED**

## Plan

<!-- populated by /planning:plan -->
