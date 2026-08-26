# L1-derivability — `L-docs-topics`

57 files, all of `docs/topics/**` except this sweep's own slice.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 57 |

No deletions, no pointer conversions. This group was the sweep's expected harvest, so the negative
result is stated with its evidence rather than as an assertion.

## Why every file keeps

### Nine of eleven slices carry open phases

A contract slice is prunable once its work is done. Nine of the eleven are not done. Phase markers,
read directly:

| Slice | Evidence |
|---|---|
| `autonomy-ignition` | `docs/topics/autonomy-ignition/PLAN.md:198` — `### Phase 4: Accumulation watch [DOING — standing]` |
| `ladder-climb-roadmap` | `PLAN.md:92` `Phase I: Ignition (#778) … [TODO]`; `:200` `Phase III … [TODO — gated on Phase I evidence]`; `:211` `Phase IV … [TODO — gated on Phase I demonstrable]`; `:223` `Phase V … [TODO — armed, not planned]` |
| `context-engineering-claude-5` | `PLAN.md:5` — `Status: **in progress** — shape decided (a component, not a runbook), seam resolved, proportionality gate closed. Phases 1, 2, 2.5, and 5 are done; design continues at Phase 3.` Phases 10 and 11 remain `[TODO]` (`:755`, `:871`) |
| `fresh-eyes-checkpoint-audit` | all four phases `[TODO]` (`PLAN.md:103,183,218,244`) — the wave-2 work has not started |
| `plugin-audit-port` | `PLAN.md:443` — `#### Phase B7: Operator cutover (post-merge, HITL) [TODO]` |
| `shadowed-skill-renames` | `PLAN.md` closes with `(To be filled by /planning:plan — or proceed directly; the PR sequence above is execution-ready.)` and a live `### Deferred questions` block with three unresolved arbiters |
| `interview-batch-rounds` | `PLAN.md` closes with `<!-- empty — populated by /architect -->` and three unresolved deferred questions |
| `ai-adoption-ladder` | the seven `design/RESEARCH-*.md` files plus `design/design-threads.md` are the research substrate the roadmap's open phases consume |
| `commit-convention-well-known-path` | cited as the live design record by `docs/conventions/commit-convention/README.md:176` |

Deleting a slice with open phases destroys the plan the next session resumes from.

### The two closed slices still own non-derivable facts

`loop-engineering-codification` executed all six phases (`PLAN.md` tail: "the record of what
executed"). It nevertheless owns withdrawn recommendations and dated external verifications that
exist nowhere else. `docs/topics/loop-engineering-codification/PLAN.md:127`:

> The earlier `pull_request.closed` recommendation is withdrawn rather than narrowed.

A withdrawn recommendation is the Factor 4 "decisions" class in its purest form: exploration
recovers the current state, never the rejected option or the reason it was rejected. The same file
carries version-stamped upstream facts ("verified 2026-07-24") about entitlement and billing
behavior that live outside this repository entirely.

`fable-field-guide-audit` (22 files) had its remediations adopted into `plugins/playbooks/skills/fable-5/`
by PR #1261. It still owns three non-derivable classes:

- An external artifact. `docs/topics/fable-field-guide-audit/source-article.md` is a captured web
  article (Thariq Shihipar, Anthropic, 2026-07-06) that the repository holds nowhere else.
- Operator decisions. `docs/topics/fable-field-guide-audit/repair-ledger.md:21`:
  > **dropped** — a proposed remediation the operator declined. No edit, and it is not deferred
  > work.
  Deleting that record invites the next audit to re-propose every declined item.
- Review provenance. `repair-ledger.md:3-6` records that `disposition-review.md` and
  `codex-review.md` findings were deliberately not folded back into `dispositions.md`, "by design,
  so the reviews stay independent artifacts". That is a methodological decision about the artifacts
  themselves.

### Pruning these slices belongs to #1419, not to this sweep

`scripts/contract-slice-baseline.txt` grandfathers exactly these eleven slugs and names the exit
condition:

> Done when this file lists no slugs and docs/topics/ is empty on main (#1419).

and, earlier in the same file:

> the existing 19 are graduated and pruned one at a time under #1419.

The word that binds L1 is **graduated**. `docs/conventions/topic-docs/README.md:482` makes
graduation a precondition of the prune:

> Before merge, durable outcomes graduate: architectural decisions and specs through the
> **knowledge-vault seam** … and actionable follow-ups through the **work-item tracker seam**.

A docs-hygiene lane that deleted these directories would execute step 4 while skipping step 3, which
is the one mechanism protecting the ungraduated decisions above. L1 defers the whole group to #1419.

### Four slices are cited from durable documents

Deleting any of these breaks a live citation in a permanent doc, which is an L4 problem this lane
would be creating rather than solving:

| Slice | Citing durable doc |
|---|---|
| `commit-convention-well-known-path` | `docs/conventions/commit-convention/README.md:176` |
| `shadowed-skill-renames` | `docs/MIGRATION-PLAYBOOK.md:437` |
| `plugin-audit-port` | `docs/adr/0005-bound-instruction-surface-work-by-question-not-population.md:326` |
| `interview-batch-rounds` | `docs/upstream/mattpocock-skills.md:128` |
| `ai-adoption-ladder` | `docs/upstream/mattpocock-skills-v12-map.md:94` |

## Cross-lane observations

- L3-ssot: within `fable-field-guide-audit`, the fourteen `findings/S*.md` per-section verdicts are
  substantially re-stated in `dispositions.md` and then again in `repair-ledger.md`. That is
  doc-to-doc duplication, which the rubric routes to `extract-ssot`, not to a deletion here. The
  S-files still hold per-claim `file:line` evidence the downstream ledgers summarize away, so any
  dedup must preserve the evidence rows.
- L2-progressive-disclosure: `docs/topics/context-engineering-claude-5/PLAN.md` is 88 KB and
  `design/rerun-contract.md` is 78 KB, both well past a comfortable single-read budget.
