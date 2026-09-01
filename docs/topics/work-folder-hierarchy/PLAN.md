# work-folder-hierarchy

## Brief

The Brief for this effort is locked and durably recorded in PR #3552's
description (pre-prune commit `dd975248419d0d40083cebd9b9a009cd6a92ece4`;
epic #3554). Per the single-home rule it is referenced here, not restated.
Design threads resolving its contested shapes: `design/design-threads.md`
(all nine resolved; verifier-gated).

## Plan

Executed under the session goal directive: full delegation with
fresh-context verification on every workstream (non-negotiable), staged
substrate-first, one atomic merge.

### Deviation note

The Brief's decision 7 stages "substrate PRs first, one normative flip PR
last." This wave lands as ONE PR (#3557) on the designated task branch with
commits ordered substrate → flip. Rationale: the staging's purpose is that
nothing partial reaches main (~19 raw-URL README readers flip on merge);
a single PR is the strictest form of that atomicity, and the session's
branch constraint pins work to one branch. The commit ordering preserves
the reviewable substrate/flip separation the staging intended.

### Phase 0 — design gate (done when)

- All nine design threads resolved; fresh-context verifier CONFIRMS each
  (challenged threads fixed and re-verified before dependent phases start).

### Phase 1 — substrate (parallel workstreams, disjoint surfaces)

1. **W1 worktree carry**: `.worktreeinclude` recursive reserved-name
   patterns; `worktree-create.sh` parity + test coverage for depth-3,
   INTENT, INDEX artifacts. (T8)
2. **W2 docpage-digest rename**: `INDEX.md` → `SOURCES.md` across SKILL,
   context, templates, evals; parity invariant intact; knowledge
   CHANGELOG entry. (T6)
3. **W3 lanes home**: defaults move to `.work/lanes/`; SKILL + claude-ops
   CHANGELOG. (T7)
4. **W4 stale-slice cleanup**: the 11 pre-gate `docs/topics/` slices
   pruned with per-slug pre-prune SHAs recorded; their
   `contract-slice-baseline.txt` lines dropped; coverage audit produced.
   (Brief decision 6)
5. **W5 index-regen lib script + tests**: marker-delimited body regen from
   child headers per T1-T4; registered in the cross-plugin source
   registry; per-plugin synced copies. (blocked by Phase 0)
6. **W6 dispatch-gate rework**: exact-assigned-path grading +
   `--check-children` parity; tests updated. (T5; blocked by Phase 0)

Each workstream: worker implements → fresh-context verifier grades the
diff against the thread's criteria → orchestrator runs
`scripts/affected-tests.sh --run` + targeted suites → commit only when
clean.

### Phase 2 — normative flip (single commit series, after all of Phase 1)

- `docs/conventions/topic-docs/README.md` v3: recursive slices with lazy
  level creation (decomposition or collision, never pre-built; topic
  slices only), INDEX.md reservation + leaf conditional + read-first
  binding, frontmatter-state/marker-body split + mini-schema + ~25KB
  fail-with-hint, index-declared ordering scope, interior-freedom clause,
  corpus-seam relationship, `lanes/` reserved row, depth-proof consumer
  recipe (from W1), gate rule description (from W6).
- `topic-docs.schema.json` (only if a key changes), all ten deltas-only
  bindings, the five registered artifact-protocol copies (via the sync
  mechanism), discovery/verification/planning setup-skill restatements,
  map-corpus hard-bound line, docs-hygiene exemption roster,
  contract CHANGELOG 3.0.0 major entry.
- Fresh-context verifier grades the flip against the Brief's acceptance
  criteria list before commit.

### Phase 3 — close (done when)

- Full validation green locally; wave pushed; review findings worked to
  zero open threads; contract slice (this file + `design/`) pruned in the
  final commit with the record carried in PR #3557's body; prune gate
  green; PR merged (auto-merge, or the residual human-approval blocker
  reported as the single remaining gate).

### Acceptance

The Brief's acceptance-criteria list (PR #3552 body) is the checklist;
each Phase 1/2 verifier grades its slice of it, and Phase 3's final
verifier confirms the set end-to-end.
