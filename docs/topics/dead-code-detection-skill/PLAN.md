# dead-code-detection-skill

## Brief

### TLDR

- New skill `code-tidying:audit-dead-code` — a whole-repo, cross-file dead-code hunter, the gap no existing skill covers.
- Tool-first, model-verified: run each ecosystem's native detector, then adjudicate every candidate against dynamic-usage evidence.
- Report-only with three verdicts (`dead` / `uncertain` / `alive`); removal is delegated to `/tidy`, `/simplify`, or `work-items`.
- First-class ecosystems: .NET/C#, TypeScript/JS, Python, shell. Everything else degrades to a grep fallback, explicitly labelled.
- V1 scope is unreferenced code symbols plus orphaned files. Dependencies, config keys, assets, and feature flags are deferred to V2.

### Goal

Give the marketplace a way to find dead code that nothing has touched in a long time — the category
that lane-rotated tidying and diff-scoped simplification structurally cannot see. A run answers
"what in this repository is no longer reachable, and how confident are we?" with each finding
adjudicated against the dynamic-usage patterns static analyzers are blind to, so the report is a
list of decisions a human can act on rather than a raw analyzer dump the reader must re-verify.

### Constraints

- **Report-only.** The skill never edits source. Deletion is delegated. This is the guarantee that
  makes it safe to run casually, and it governs every other decision below.
- **Never auto-install tooling.** Detector presence is observed, not created; a missing detector
  degrades the run, it does not mutate the user's toolchain.
- **A partial sweep must never read as a complete one.** Every report states which detectors ran,
  which were skipped, and what that means for coverage.
- **House skill conventions are binding** — the classifier-family section order, the flat
  `Finding …:` / `Summary total:` record protocol (a contract with the skill's own precompute
  grep), the `${CLAUDE_SKILL_DIR}` grant string, shell-portability rules, and the full
  registration checklist (plugin.json minor bump, README roster, CHANGELOG, both regenerated
  catalogs). Reference: `.work/dead-code-detection-skill/authoring-conventions.md`.
- **Evals are a merge gate**, not optional polish: a new SKILL.md fails CI without them, and every
  shipped fixture must be consumed.
- Detector orchestration must tolerate each tool's native output shape — JSON for knip/deptry/
  staticcheck, SARIF for Roslyn and `jb inspectcode`, line-oriented text for vulture.

### Acceptance criteria

- `plugins/code-tidying/skills/audit-dead-code/` exists with `SKILL.md`, `scripts/detect.sh`,
  `scripts/detect.test.sh`, a `scripts/lib/` shapes file, `evals/evals.json`, and `evals/fixtures/`.
- The skill runs whole-repo by default and accepts an optional path/glob argument; when
  `.claude/tidy-lanes/` exists its globs are selectable as named scopes, without inheriting lane rotation.
- Every emitted finding carries one of exactly three verdicts — `dead`, `uncertain`, `alive` — and
  every `alive` finding cites the specific evidence that saved it.
- The report names every detector as ran / skipped / unavailable, and any grep-fallback finding is
  labelled reduced-confidence.
- Suppression entries are emitted as ready-to-paste text in each tool's native format; no
  suppression file is written by the skill.
- Findings are written to stdout as markdown AND persisted to the topic's `.work/` slice; handoff to
  `work-items:track` is opt-in, never automatic.
- Eval fixtures exist per first-class ecosystem, each pairing a genuinely-dead symbol with a
  dynamic-reference trap (DI registration, `getattr`, string dispatch) that must be verdicted `alive`;
  plus a guardrail case asserting the skill stays read-only when asked to fix.
- `detect.test.sh` passes; `check-skill.sh --require-evals`, `check-evals-quality.sh`,
  `check-shell-portability.sh`, `check-orphaned-fixtures.sh --check`, and
  `check-changelog-parity.sh --check` all pass; both catalog generators are regenerated and clean.
- Registration is complete: plugin.json description + minor version bump, README roster bullet and
  count, CHANGELOG entry, `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md` regenerated.

### Captured assumptions

- The three-verdict vocabulary maps onto the sibling's Tier 1 / Tier 2 convention (T1=`dead`,
  T2=`uncertain`, T3=`alive`) — revisit if the flat record protocol cannot carry a third tier cleanly.
- Shell is the weakest ecosystem (shellcheck's unused-variable checks are file-local and blind to all
  indirection), so the model pass carries most of the detection weight there, not just verification —
  revisit if shell findings prove too noisy to ship.
- Whole-repo scanning is acceptable on large .NET solutions — revisit if `jb inspectcode` runtime
  makes a default run impractical, in which case scope selection becomes mandatory rather than optional.
- `knip` covers unused dependencies almost for free in TS/JS; V1 does not report them, but the
  plumbing should not preclude it — revisit at V2.

### Out-of-scope

- Unused dependencies, dead config keys, unreferenced assets, and stale feature flags (V2 lanes).
- Any source edit or deletion — permanently out of scope for this skill by design.
- Writing to suppression config files.
- A setup skill or a dedicated `dead-code.json` config surface.
- Coverage-based (runtime) dead-code detection — "unexecuted" is not "unreachable".

### Deferred questions

- Q13 — Should V2 add unused-dependency reporting as its first extension, given knip and deptry
  already emit it? — defer until V1 ships and produces real false-positive data; **arbiter: USER-RESERVED**
- Q14 — Does a `dead-code.json` known-alive/entry-point config become necessary for reflection-heavy
  repositories? — defer until V1 false-positive rates are observed; **arbiter: USER-RESERVED**

## Plan

<!-- populated by /planning:plan -->
