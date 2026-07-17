# Design threads — proactive-vs-reactive-skills

Scope: `integration` (cross-plugin concern contract). Resolves the Brief's two
design-deferred items: index/contract schema and plugin-upgrade migration shape.
Resolved schema detail lives in `contract-spec.md` (single home); this file
records decisions + rationale only.

## T1 — Index file format + clue placement [RESOLVED]

Markdown index with YAML frontmatter (contract version) + routing table;
standards files stay pure prose; load-clues live in the index table.

- Rationale: single-home rule — clues are routing metadata, home = routing map.
  One-file read for routing (progressive disclosure); model-native format
  matching the prose it routes; security-guidance seam-2 precedent is markdown.
- Rejected: frontmatter-clues + generated index (generated tracked file needs
  regeneration on every edit — collides with no-silent-writes); YAML index
  (ecosystem-commands chose YAML because its values are opaque shell commands —
  does not hold here; the reader is the model, the content is prose).
- Drift (file added, row forgotten) is caught by idempotent setup validation.

## T2 — Surface taxonomy [RESOLVED]

Open vocabulary + recommended kinds. Surface id = free-form kebab-case;
contract documents recommended-not-mandatory kinds (ecosystem surfaces,
cross-cutting concerns). Applies-when = free-form context clues (globs + task
keywords). **No stage axis** — B6 build/review symmetry is the point; a
plan/review dimension would re-fork the criteria the design unifies.
Rejected: fixed matrix (sparse, forces cells, C1 tension).

## T3 — Layer indexing [RESOLVED]

Team index lists team files only. A tracked index cannot list gitignored
files. Personal `<name>.local.md` overlays by filename convention; standalone
`.local.md` allowed; both glob-discovered, never indexed. User-global layer:
optional own README, degrade to glob.

## T4 — Index filename [RESOLVED]

`README.md` at the standards root (accepted in T1's selected shape) — GitHub
renders it as the folder landing page; the conventional discovery anchor.

## T5 — Contract version surface [RESOLVED]

Frontmatter key `standards-contract: <semver>` in the index only (accepted in
T1's selected shape). Standards files carry no version — the contract versions
index schema + resolution semantics, not consumer content. This key is what
upgrade detection (T6) reads.

## T6 — Plugin-upgrade migration shape [RESOLVED]

Inside re-runnable setup — no separate migrate action. Setup auto-detects the
version delta (index frontmatter vs bundled contract), explains the gap, and
guides/offers migration. Rationale: setup already owns "converge consumer
config to current contract" (B3e); one entry point; fewer skills; precedent
(ecosystem-commands majors deliver via version bump + setup). Companion rule:
skills reading an older-version index degrade to best-effort + surface
"index at vX, contract at vY — re-run setup"; never auto-rewrite.

## T8 — `.claude/rules` vs `docs/standards/` division [RESOLVED]

Adopted: division-of-content rule + pointer pattern (user confirmed,
conditional on doc-backing — verified against the official memory page fetched
2026-07-17).

Verified facts (<https://code.claude.com/docs/en/memory>):

- Path-scoped rules "trigger when Claude reads files matching the pattern, not
  on every tool use" — push surface; fires at implement/review time, NOT at
  plan time for not-yet-written code; not enumerable.
- Rules without `paths` load at launch (ambient, always-on cost).
- `@import` expands at launch (documented for CLAUDE.md; behavior inside rules
  files undocumented — excluded from the design rather than relied on).
- Markdown links are not auto-followed (no documented mechanism; on-demand
  files are read "using its standard file tools"); an imperative directive in
  a fired rule IS acted on — "context, not enforced configuration".

Decision:

1. **Rules = push, standards = pull.** Short imperative path/always directives
   → consumer's `.claude/rules` (consumer-owned surface). Substantial
   criteria/prose → `docs/standards/` (per-trigger context cost too high for
   rules; criteria mode needs an enumerable index).
2. **Pointer pattern, not duplication.** A path-scoped rule MAY be a thin
   pointer directive to a standards file (lazy: fires on read, model pulls the
   file). Never `@import`; never restated content. Setup MAY offer generating
   pointer rules — interactive setup absorbs the `.claude/` write-guard
   prompt; never silent.
3. **Why the index survives "rules are more proactive":** rules fire on file
   reads only; plan-time grounding and criteria enumeration need the pull
   surface. The two compose.
4. **Ambient no-re-read stands:** fired-rule content is ambient; grounding
   pulls only index-routed files not already in context.

## G1 — External-path index rows [RESOLVED, conditional]

Index rows MAY route to repo-relative files outside the standards root (index
is a routing map, not a store; adoption without forced reorg — C1). User
conditions, adopted into the contract: (a) validation duty — setup validates
every listed path exists; consumer link-check lane (e.g. lychee) recommended
to cover the index; (b) Boy Scout rule — a skill hitting a broken row surfaces
it and offers the fix, never silent, never skipped quietly. Overlay shadowing
stays defined only for in-root files.

## G2 — Standards-root relocation record [RESOLVED]

`.claude/standards.yaml` concern file, `standards_dir` key, topic-docs shape;
written by interactive setup only when the consumer relocates (absent =
default `docs/standards/`). userConfig verified unfit this session
(<https://code.claude.com/docs/en/plugins-reference>): values store in USER
settings only — "entries in a project's `.claude/settings.json` or
`.claude/settings.local.json` are ignored" — and the key is per-plugin, so a
team value shared by two consuming plugins cannot live there. User-global
layer relocation: deferred, trigger = someone actually needs it.

## T7 — Test-seam posture [directional]

Acceptance criteria already fix the seam: exercise pilot skills against
fixture repos via `--plugin-dir` (index-present, index-absent, mixed-layout
cases) + grep gates for binding references and hardcoded paths. One seam,
highest level — no unit seams inside skill prose. Detail → /architect test
strategy.

## Deferred (tagged)

- User-global layer relocation (G2) — trigger: real need.
- Binding-copy sync mechanics (B3c) → /architect.
- Per-skill step placement (B3d) → /architect.
- Wave-2 inventory → USER-RESERVED.
