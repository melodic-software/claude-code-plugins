# dead-code-detection-skill

## Brief

> **Revision 2 (2026-08-23).** Revision 1 was validated by three independent fresh-context
> agents (`/planning:audit-answers`); all twelve decisions drew at least one evidence-backed
> dissent and the Brief was rewritten. The material changes: the skill moves from
> `code-tidying` to `codebase-health`; shell is demoted from first-class to a model/grep lane
> and Go + Rust are promoted in; .NET becomes an opt-in build-requiring lane; removal is
> delegated through the real `review-findings` relay instead of `/tidy` and `/simplify`;
> the verification pass gains a cap; persistence moves behind an explicit flag; strict
> zero-config is replaced by the sanctioned `userConfig` + suppression-record channel; and
> evals gain canned tool-output fixtures because CI executes no eval and installs no detector.

### TLDR

- New skill `codebase-health:audit-dead-code` — a whole-repo, cross-file dead-code hunter, the gap no existing skill covers.
- Tool-first where a real detector exists (TS/JS, Python, Go, Rust); an explicitly-labelled model/grep lane where none does (shell); .NET opt-in because its only capable tool builds the solution.
- Report-only with three verdicts (`dead` / `uncertain` / `alive`); removal delegated through the `review-findings` relay to `review:fanout fix`.
- Every candidate is adjudicated against dynamic-usage evidence under a `--max` cap with a printed cost estimate; findings persist only behind `--persist-findings`.
- V1 scope is unreferenced code symbols plus orphaned files, with orphaned-file coverage stated per ecosystem rather than claimed globally.

### Goal

Give the marketplace a way to find dead code that nothing has touched in a long time — the
category that lane-rotated tidying and diff-scoped simplification structurally cannot see. A run
answers "what in this repository is no longer reachable, and how confident are we?" with each
finding adjudicated against the dynamic-usage patterns static analyzers are blind to, so the
report is a list of decisions a human can act on rather than a raw analyzer dump the reader must
re-verify. A second run must be quieter than the first.

### Constraints

- **Report-only.** The skill never edits source. Deletion is delegated. This is the guarantee
  that makes it safe to run casually, and it governs every other decision below.
- **Read-only means the process too, not just the source tree.** Any detector that builds,
  restores, or executes project code (`jb inspectcode`, `dotnet build`) is opt-in behind an
  explicit flag and never part of a default run — a narrow-looking `detect.sh` grant must not
  become blanket approval to compile the user's solution.
- **Never auto-install tooling.** Detector presence is observed, not created.
- **A partial sweep must never read as a complete one.** Every report states which detectors ran,
  which were skipped, and what that means for coverage. A run where every detector is missing
  must not exit "0, clean" — that is the false-green class the `liveness-assertion` convention forbids.
- **Candidate scope and reference-search scope are separate.** A scoped run still searches
  references repo-wide; otherwise every symbol defined inside the scope and used outside it is a
  false `dead`.
- **The precompute block must not run detectors.** The classifier family runs `detect.sh` on every
  invocation; `detect.sh` inventories detector presence and cheap candidates only.
- **Owned conventions bind**: `detector-findings` (the only route from a detector to a remediation
  surface), `finding-suppression` (the record that stops a judged finding resurfacing),
  `topic-docs` (destination resolution; `.work/` is the never-committed memory tier),
  `ecosystem-commands` (the consumer-declared per-ecosystem command/glob seam),
  `permission-rule-hygiene` (package-runner grants are inert under auto mode, which is the default),
  and the `audit` verb contract (mutation only behind an explicit override).
- **Evals are a presence-and-lint gate only** — CI executes no eval and installs no detector, so
  behavioral correctness must be carried by `detect.test.sh` over recorded fixtures.

### Acceptance criteria

- `plugins/codebase-health/skills/audit-dead-code/` exists with `SKILL.md`, `scripts/detect.sh`,
  `scripts/detect.test.sh`, a `scripts/lib/` shapes file, `evals/evals.json`, `evals/fixtures/`,
  and `context/` spokes planned up front so `SKILL.md` stays under the 200-line soft target.
- Ecosystem tiers are stated explicitly in the skill body: **tool-backed** — TS/JS (knip),
  Python (vulture), Go (staticcheck U1000 + `x/tools` deadcode), Rust (rustc `dead_code`);
  **model/grep** — shell and everything else; **opt-in, build-required** — .NET
  (`jb inspectcode`), never in a default run.
- Orphaned-file coverage is stated per ecosystem in the same table that names detectors, not as a
  global scope claim.
- Every emitted finding carries one of exactly three verdicts — `dead`, `uncertain`, `alive` —
  and every `alive` finding cites the specific evidence that saved it in the human-facing report.
- Each ecosystem's run precondition (`installed?` / `built?` / `restored?`) is checked and
  reported; an unmet precondition yields a **degraded** run verdict distinct from "no findings".
  knip's `unresolved`/`unlisted` categories are excluded as findings but retained as run-health signals.
- The verification pass is bounded: a `--max <n>` cap, a printed wall-clock/token estimate before
  the expensive phase, a `n dropped by cap` line in the summary, and subagent fan-out rather than
  inline adjudication.
- Suppression entries are emitted as ready-to-paste text in each tool's native format; no
  suppression file is written by the skill. Findings with no native suppression target — grep-lane
  and `uncertain` — route to the `finding-suppression` record instead.
- Persistence is off by default and available behind `--persist-findings`, conforming to the
  `review-findings` file shape, written to the branch-scoped findings directory resolved through
  the topic-docs ladder (never a hardcoded `.work/`), and **excluded from the next run's scan set**.
- Configuration uses the sanctioned channels only: `userConfig` with zero-config-preserving
  defaults (vulture `--min-confidence`, knip default vs `--production`, the `--max` cap) and the
  `finding-suppression` record for known-alive entries. No bespoke `dead-code.json`.
- `codebase-health:setup`'s `check` action reports detector presence and the install line for each
  missing tool.
- Eval fixtures include **canned tool-output fixtures** — a real knip `--reporter json` blob, a
  SARIF log, a vulture text block, a shellcheck `--format=json1` blob — driving the parsing and
  adjudication layers hermetically in CI; live-detector cases are explicit skips. Paired
  dead-symbol/dynamic-reference-trap discrimination is asserted in `detect.test.sh`, not only in
  `evals.json`. A read-only guardrail case asserts the skill declines to fix when asked.
- The skill's description routes explicitly against `/code-tidying:tidy` Beck #2, and
  `tidyings.md` #2 points back at this skill — one act, one stated boundary.
- `detect.test.sh` passes; `check-skill.sh --require-evals`, `check-evals-quality.sh`,
  `check-shell-portability.sh`, `check-orphaned-fixtures.sh --check`, and
  `check-changelog-parity.sh --check` all pass; both catalog generators are regenerated and clean.
- Registration is complete for `codebase-health`: plugin.json description + minor version bump,
  README roster bullet and count, CHANGELOG entry, `docs/CATALOG.md` and
  `docs/SKILL-CHEAT-SHEET.md` regenerated. Separately, `code-tidying/README.md`'s stale
  "Three skills" roster (missing `audit-comment-residue`) is repaired.

### Captured assumptions

- A shell fixture holding a genuinely-dead *function* trips no CI check (measured: shellcheck
  finds none), so only an unused-*variable* fixture would need a CI exemption — revisit if the
  fixture set needs one anyway.
- `codebase-health`'s existing dimension seam and graceful-degrade section can host an
  externally-toolchained skill without changing that plugin's character — revisit if its setup
  criteria or config surface fight the detector roster.
- Go and Rust detectors are standard-toolchain and JSON-native, so they cost less to support than
  the ecosystems they replace in the first-class tier — revisit if their entry-point/`cfg` false
  positives prove worse than expected.
- Recorded tool-output fixtures stay valid across detector versions — revisit when a tool's output
  schema changes; the fixture's captured tool version is recorded alongside it.

### Out-of-scope

- Unused dependencies, dead config keys, unreferenced assets, and stale feature flags (V2 lanes).
- Any source edit or deletion — permanently out of scope for this skill by design.
- Writing suppression files or the `finding-suppression` record on the skill's own initiative.
- Coverage-based (runtime) dead-code detection — "unexecuted" is not "unreachable".
- Reimplementing `/code-tidying:tidy`'s two-layer lane-merge resolution; lane globs are not
  consumed in V1, and scope selection is an explicit path/glob argument instead.

### Deferred questions

- Q13 — Should V2 add unused-dependency reporting as its first extension, given knip and deptry
  already emit it? — defer until V1 ships and produces real false-positive data; **arbiter: USER-RESERVED**
- Q14 — Does a known-alive/entry-point config beyond the `finding-suppression` record become
  necessary for reflection-heavy repositories? — defer until V1 false-positive rates are observed,
  which the `--persist-findings` record now makes measurable; **arbiter: USER-RESERVED**
- Q23 — Should the skill eventually offer a quarantine/staged-removal workflow, given the
  `dead-code-sweep` routine class mandates a 30–90 day quarantine floor that no delegation path
  currently provides? — defer until a routine is actually built on this skill; **arbiter: USER-RESERVED**

## Plan

<!-- populated by /planning:plan -->
