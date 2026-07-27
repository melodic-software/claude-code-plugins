# Changelog — topic-docs convention

## 2.4.0 — 2026-07-27

- **An Ephemeral row joins the tier table** (additive). The table sorts
  documents by one question — does anything downstream enforce against
  this? — which cannot express lifetime, so its finest-grained cell, the
  memory tier, conflated state a later reader must find with files
  nothing downstream ever reads again. With no row naming the second kind, two plugins
  independently invented the same answer and both reached for the
  session scratchpad, an undocumented harness path (zero occurrences in
  the full docs corpus, keyed by working directory, and declined three
  times upstream as a supported surface). The convention registry's
  trigger — an owner doc before a second plugin adopts — had already
  fired. The row states five rules (one deterministic path; the lifetime
  outlives the call, so a producer that returns a path never deletes the
  file before returning; never the scratchpad; nothing durable; the FORM
  of any temp-root override is a manifest `userConfig` rather than a
  tracked key), carries a re-derivation trigger, and records why
  git-visibility, promotion-stage, and write-contention each needed no
  change.

  Rule 2 is stated because both existing adopters hand their file back
  as a path for the user to open — a `finally` cleanup would race the
  reader and return a dead path. The row deliberately does **not**
  promise the file dies with the session: no documented Claude Code
  mechanism prunes that temp tree (`cleanupPeriodDays` is scoped to
  `~/.claude/`, a different tree), so the honest guarantee is that the
  file OUTLIVES the invocation and is reclaimed only when the platform
  reclaims its temp tree. That is why one run writes one file and never
  a tree.

  Two claims are stated as constraints rather than capabilities, because
  neither capability exists today. Rule 1 does not route
  `CLAUDE_CODE_TMPDIR` into the temp primitive: that variable overrides
  the temp directory Claude Code uses for its own internal files, and
  the env-var reference states that unsandboxed Bash commands inherit
  the shell's `$TMPDIR` unchanged, so a plugin shelling out to `mktemp`
  never observes it. Rule 5 fixes the form an override takes *if* a
  plugin offers one; neither current adopter declares `userConfig`, and
  the rule no longer reads as a promise that one is available.

  Minor, not major: no tier moves, no `topic-docs.yaml` key is renamed,
  the slug spec is untouched, and no visibility guarantee changes — the
  ephemeral row is slug-less and invisible to every other execution
  context by construction, so it takes no row in the visibility matrix.
  The eight bindings need no synchronized adoption wave.

## 2.3.0 — 2026-07-26

- **The `.worktreeinclude` template carries sub-slices** (additive). Its
  patterns matched one level — `.work/*/RESEARCH.md` — while a producer
  may write `<memory_dir>/<slug>/<sub-slug>/`, the layout used when one
  slice holds more than one run: a parallel fan-out assigning a sub-slice
  per topic, or a run that found the slice root already occupied by
  unrelated work. Glob patterns do not descend on their own, so a spawned
  worktree carried the top-level index and silently dropped every nested
  index, sidecar, and ledger. That partial set is worse than carrying
  nothing, because the receiving session sees an artifact and cannot tell
  it is incomplete. Five nested patterns are added; nothing existing
  changes meaning and no visibility guarantee moves — a sub-slice was
  always inside the slice, it was simply unreachable by the template.

## 2.2.0 — 2026-07-25

- **"Implementers restate the rules; they do not share a source"** (new,
  additive guidance). The fleet had left implicit what a setup skill's
  relationship to this contract is, so byte-identical prose across two
  setup skills read as copy-paste inviting extraction into
  `scripts/cross-plugin-source-registry.txt`. It is not: a `SKILL.md` is
  the instruction surface a session loads and cannot defer at runtime to
  a document the consuming repo lacks, so every implementer restates.
  The section names the live evidence — `discovery` and `verification`
  agreeing byte-for-byte while `planning` already diverges on the
  memory-root `.gitignore` owner and on the empty-mapping case — states
  why a shared fragment would be a second owner for rules this contract
  already owns, and records the trigger that would reopen extraction. No
  tier, key, slug-spec, or visibility change.

## 2.1.0 — 2026-07-23

- **Implementers table: architecture row added** (additive). The architecture
  plugin's deepening lens writes its per-lens candidate ledger
  (`deepening-candidates-<timestamp>.md`) to the memory tier via a delta-doc
  binding, replacing its prior broken `${CLAUDE_PLUGIN_DATA}` default (the
  token never substituted in skill content, and even resolved it is
  machine-global). No tier, key, slug-spec, or visibility change.

## 2.0.0 — 2026-07-17

Visibility semantics are now normative contract guarantees. No tier moves, no
`topic-docs.yaml` key changes, no slug-spec changes — the schema is untouched.
The Versioning rule now counts a visibility-guarantee change as major; this
release is the first such change, and the rule amendment is what makes the
major label honest.

- **Visibility across execution contexts** (new, normative): context × tier
  visibility matrix; four native mechanisms — `worktree.baseRef: "head"` in
  committed project settings (verified honored at project scope on CC 2.1.212,
  including from linked worktrees), `.worktreeinclude` one-way creation-time
  copy of gitignored memory files, by-value worker returns with the
  orchestrator writing contract/durable tiers in the parent checkout, and the
  work-item tracker as the cross-lane index (markdown-in-tickets as a primary
  artifact store rejected: not diffable, no review gate, drifts from code).
  Caveats documented: a `WorktreeCreate` hook makes `.worktreeinclude` inert;
  a personal `.claude/settings.local.json` silently overrides the committed
  `baseRef` machine-wide, so nothing may assume it universally in force.
- **Pointer discipline on durable surfaces** (new, normative): tickets, PR
  bodies, and promoted docs never cite prunable contract paths or gitignored
  memory paths — cite the PR, the promoted location, or distilled values.
- **Consumer adoption**: settings + `.worktreeinclude` templates; repository
  files never travel with marketplace-installed plugins, so consuming repos
  self-apply; rollout caveats (untracked-settings pull collision, Windows
  worktree path limit).
- **Implementers table reconciled with the fleet**: verification and toolchain
  rows added; a Binding column distinguishes delta-doc implementers from
  adopt-by-reference rows (knowledge, claude-ops, docs-hygiene) with the
  reason each needs no delta doc; the verification manifest and baselines
  moved from the implementation row to the new verification row, matching the
  plugins' actual bindings.

Mixed-fleet window: installed plugin caches and in-flight branches keep 1.x
text until they update. Safe because no tier, key, or slug-spec changed —
divergence is doctrinal, never layout-corrupting. In-flight branches sweep
stale visibility text when they merge.

## 1.0.1 — 2026-07-15

- Reserve `vault_backend: gitbook` without enabling writes: concern files preserve the key, skills
  report its deferred state, and durable promotion uses `docs` without GitBook API/MCP or Git Sync
  writes. A mirror requires separately reviewed automation that keeps git authoritative.

## 1.0.0 — 2026-07-14

Initial contract. Replaces four divergent conventions
(`.claude/notes/<slug>`, `.claude/handoffs/`, `.claude/review/`, legacy
unscoped `.work/<slug>`) with:

- Two tiers on one slug: memory (`.work/<slug>/`, self-ignoring) and
  contract (`docs/topics/<slug>/`, committed on the task branch, pruned
  before merge with context pointers).
- Tracked concern file `.claude/topic-docs.yaml` as the consumer-side
  SSOT, with a six-rung resolution order and legacy `notes_dir` knobs as
  a deprecation grace path.
- Runtime guards: committed-tier `git check-ignore` assertion; memory
  self-ignore verify-or-create; no consumer root-`.gitignore` edits.
- Windows-safe slug and filename spec; single-home rule; redaction bar
  for committed evidence.
- Graduation edges: work-item tracker seam (tickets) and knowledge-vault
  seam (durable docs; in-repo `docs/` default backend).
- Removed kinds: `history.md`; default-persisted `brainstorm.md`.
