# Changelog — topic-docs convention

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
