# Skill dispatch-posture audit — coverage ledger

Corpus: every non-`setup` skill in `plugins/*/skills/*/SKILL.md` in this marketplace. Enumerated
by script, not by hand. **138 skills, 11 batches, zero skipped. Sweep complete.**

Excluded and why:

- `*/skills/setup/` (39 skills) — install/config surface, never a dispatch candidate.
- `*/skills/*/vendor/SKILL.md` and other nested `SKILL.md` (7 files) — upstream-owned
  materializations; changes return through the owner's sync path, never a local edit.

This file is an **index**. Each row carries the verdict and a pointer to the batch artifact holding
its evidence-cited rationale; the rationale is not copied up. That is Decision 4's shape applied to
this ledger itself.

## Audit criteria

Each skill gets a verdict against the decisions locked in
[`docs/topics/discovery-subagent-dispatch/PLAN.md`](../discovery-subagent-dispatch/PLAN.md).

**Verdict** — one of:

- `DISPATCH-DEFAULT` — should spawn a subagent by default; main context gets a pointer + summary.
- `DISPATCH-OPTIONAL` — benefits from a dispatch escape hatch, but inline stays the default.
- `INLINE-ONLY` — must stay in main context. Justified only by a hard blocker, named explicitly.
- `NO-CHANGE` — neither applies; the skill is short, conversational, or already dispatches.

**Mechanism** (dispatch verdicts only) — one of:

- `plugin-agent` — custom subagent definition. Fresh context, no conversation history.
- `context-fork` — skill-level `context: fork`. Fresh context, no conversation history.
- `inline-dispatcher` — main-context tier selection. Required whenever the skill needs `Workflow`.
- `history-fork` — the Agent tool's `subagent_type: "fork"`, the **only** mechanism that inherits the
  live transcript. Required by any skill whose audit input IS the conversation. Rollout-gated by
  `CLAUDE_CODE_FORK_SUBAGENT` and degrades to *stop*, not to *inline*. Cost scales with transcript
  length rather than task size, so it inverts the context-saving premise on a long session.

**Preload vs. runtime invocation** — a `plugin-agent` can receive its discipline two ways, and they
are not equivalent. `skills:` preload injects the skill content at startup; runtime invocation grants
the `Skill` tool and the agent calls it. Every agent this marketplace ships today
(`review/` ×6, `plugin-quality/` ×1) uses runtime invocation, none uses `skills:`. That is the safer
default: `!`-precompute blocks, `allowed-tools` grants, and `${user_config.…}` substitution are
documented to run when a skill *runs*, and whether they fire under `skills:` preload is
**unverified**. Prefer runtime invocation with the agent body mandating the call; reserve `skills:`
preload for skills carrying none of that load-time machinery.

**Hard blockers that force `INLINE-ONLY`** — a skill stays inline if its contract needs any of:

- `Workflow` — unavailable in every subagent.
- `TaskCreate`/`TaskGet`/`TaskList`/`TaskUpdate` — dropped by the background filter.
- `EnterPlanMode`/`ExitPlanMode`, `ScheduleWakeup`, `TaskOutput` — dropped everywhere.
- **A live user, mid-flow.** Two-part test, and both parts must hold. First, name the blocker as the
  absence of a USER, never as the absence of `AskUserQuestion`: several skills gate that tool behind a
  `use_ask_user_question` config defaulting OFF and fall back to inline prose rounds, equally
  unreachable from a subagent, so a tool-shaped justification reads as defeasible. Second — and this
  is where most over-blocking happens — needing user input is **not by itself** a blocker. The Brief
  establishes the degrade path: return open questions as text, parent re-surfaces them. Interaction
  blocks dispatch ONLY when it is **mid-flow load-bearing** (the run cannot proceed correctly without
  the answer, so deferring it either stalls the run or lets it continue on an unconfirmed branch) or
  when it **gates an irreversible action**. A skill that merely reports questions at the end is
  dispatchable.
- **A terminal that must move the invoker's own session** (worktree entry, plan-mode transition,
  session handoff). A subagent cannot relocate its parent.
- **The live transcript**, when the skill's input is the conversation itself. Fresh-context
  mechanisms discard it; only `history-fork` inherits it.
- **Its own `Agent` fan-out**, when the skill mandates fresh-context subagents as a correctness
  control. Dispatching such a skill silently degrades that mandatory step to inline self-critique
  unless `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` is set — which Decision 3 keeps optional. Record the
  recursion explicitly.

**Not a blocker** (adjudicated in B07, applied fleet-wide): a skill's `allowed-tools` grant. It is
pre-authorization that suppresses prompts, not state the parent must observe live; the commands run
under whatever `Bash` permission the dispatched agent inherits. Whether the grant survives a `skills:`
preload is an implementation caveat, not a permissibility question.

**Signals that argue for `DISPATCH-DEFAULT`:**

- The skill reads many files or fetches many pages whose raw content the parent never re-reads.
- It already writes a durable artifact (or should).
- Its output is a report, an inventory, an audit, or findings — not an in-conversation decision.
- It already has a `-deep` sibling, or its own text warns about context cost.
- **Independence** — a verify/review-shaped skill that requires producer ≠ critic satisfies that
  invariant by construction when dispatched. The argument is correctness, not only token cost.

**Progressive-disclosure check** (independent of the dispatch verdict) — record in the rationale when
the skill's artifact should become an index-plus-sidecars set rather than one flat document.

## Results

| Verdict | Count | Share |
|---|---|---|
| DISPATCH-DEFAULT | 22 | 16% |
| DISPATCH-OPTIONAL | 44 | 32% |
| INLINE-ONLY | 39 | 28% |
| NO-CHANGE | 33 | 24% |
| **Total** | **138** | |

**Ratified 2026-07-24, coverage complete.** These counts reflect the eight independently-decided
questions (D1–D8, see [`decide/SUMMARY.md`](decide/SUMMARY.md)) plus the D9 close-out, applied in full.
The pre-ratification distribution was DISPATCH-DEFAULT 20 / DISPATCH-OPTIONAL 29 / INLINE-ONLY 57 /
NO-CHANGE 32. **INLINE-ONLY fell from 57 to 39 — nearly a third of it did not survive** the inverted
burden of proof (dispatch is the default; INLINE-ONLY is the claim needing justification). The dominant
cause was a single systematic defect: multi-action skills graded on their heaviest action, so a
mutating or interactive action set the verdict while a read-only sibling in the same skill carried no
blocker and held nearly all the context volume.

**Every INLINE-ONLY verdict has now been read against primary text.** The 32 rows that had been upheld
on inherited rationale were opened in full by the D9 close-out; 3 changed, 28 were upheld with their
blocker restated in the criteria's own terms, and 1 was tested as a challenge and withdrawn.

Distribution recomputed by script from the rows below, not hand-tallied.

Transcription from the 11 batch artifacts into this index was verified by script (regex-extract
`(skill, verdict)` pairs from both sides, diff). It caught one stale value —
`/session-flow:orient`, which B09 revised to DISPATCH-OPTIONAL / `history-fork` after the criteria
amendment — now corrected here. No other divergence.

## Merge-time normalization — outcome

The criteria were amended mid-sweep, so batches were not judged against identical text. Three passes
were specified; their status:

1. **Over-blocked interaction** — the mid-flow / irreversible-action rule was added after B01–B08
   returned. B02, B07, B10, and B11 applied it natively (B10 explicitly declines bare-`AskUserQuestion`
   blocking; B11 clears `Monitor` and `gh`-mediated interaction). B01, B04, B05, and B06 predated it,
   so their INLINE-ONLY rows were re-tested against it here.

   **Coverage correction — adversarial audit finding C1.** The earlier "21 rows, zero flips" claim was
   overstated. Scripted INLINE-ONLY counts per batch: B01 4, B02 4, B03 6, B04 5, B05 4, B06 8, B07 1,
   B08 9, B09 10, B10 2, B11 4 (57 total). **B03 and B08 fell into neither the applied-natively set nor
   the re-tested set.** True picture: **13 rows re-tested row by row** (B01 + B04 + B05) — zero flips;
   **8 rows (B06) tested at summary-argument level only**; **15 rows (B03 6 + B08 9) never tested**.

   The exposure is demonstrated, not hypothetical: `B03:22` justifies `/discovery:blindspot` as
   INLINE-ONLY via "an interactive user turn a subagent cannot take (`AskUserQuestion` is filter-1
   blocked)" — the exact tool-shaped form these criteria reject — and validator-B independently flipped
   that row to DISPATCH-OPTIONAL.

   **Re-test complete** — [`verify/renorm.md`](verify/renorm.md). Of the 15: **12 confirmed, 3 flip.**
   But only 4 of the 12 confirmed cleanly; **8 had their stated justification replaced, narrowed, or
   voided** while the verdict survived — the rejected tool-shaped form in `disk-hygiene:clean` and
   `docs-hygiene:rename-references`, and a transcript-dependency leg voided by `history-fork` across
   five `re-anchor` correctors. C1's concern was well founded: these rows were resting on reasoning
   the criteria no longer accept, even where the answer happened to be right.

   The 3 flips — `/discovery:blindspot`, `/re-anchor:point-dont-copy`, `/re-anchor:reuse-or-replace`,
   all INLINE-ONLY → DISPATCH-OPTIONAL — turned on the start-of-run-gate rule and the
   parent-supplied-scope principle. Both were ratified on 2026-07-24 (D3, D4), so **all three are now
   applied** to the rows below. `/discovery:blindspot` had triple corroboration: this re-test,
   validator-B blind, and D3's dedicated agent, none seeing the others.

   The 13 genuinely tested each rest on a mid-flow gate (interview loops in `education:teach`,
   `event-storming:*`, `planning:*`, `naming:name-it-better`'s terminal human pick), an
   irreversible-action gate (`claude-memory:stateless` purge, `firecrawl:update`'s global install and
   SKILL.md rewrite, `github:advise --apply`), or a tool blocker independent of interaction
   (`implementation:implement`'s `TaskCreate` + plan mode).
   **Second coverage correction — D9 finding.** Summing the per-batch INLINE-ONLY counts against the
   buckets above accounts for only 47 of 57: applied-natively (B02, B07, B10, B11) 11 + renorm
   row-tested (B01, B04, B05) 13 + summary-level (B06) 8 + never-tested-then-renormed (B03, B08) 15.
   **B09's 10 rows sit in no bucket at all.** Honest counterweight, from reading them: B09's
   rationales independently reason in the *amended* criteria's terms — they cite `history-fork` by
   name and invoke its cost-inversion clause — and this file's own transcription note records that
   B09 revised `/session-flow:orient` **after** the amendment. B09 was worked post-amendment but never
   credited with it. All ten were subsequently opened and read in full by the D9 close-out.

   **Coverage is now complete.** D9 opened all 32 previously-unverified rows in full (32/32, no
   targeted reads, no inherited rows), deriving the set by scripted set difference rather than by
   hand. Every INLINE-ONLY verdict in this ledger has now been read against primary text.

2. **Same-plugin same-blocker splits** — one caught and corrected in-batch (B10's babysit pair).
   No cross-batch split found: no plugin spans two batches.
3. **Delegation over dispatch** — identified in B10 (`songwriting:suno`) and applicable more broadly.
   Not applied as a re-verdict; it is a plan-step reduction, recorded in the Brief.

**Two items the normalization surfaced rather than resolved:**

- `/implementation:implement-dispatch` reads equally as NO-CHANGE ("already dispatches — it *is* the
  dispatcher") as it does INLINE-ONLY. B05 flagged it for ratification rather than picking. Left as
  INLINE-ONLY pending that call; the practical outcome is a no-op either way.
- Four INLINE-ONLY rows contain a clearly dispatchable **sub-action**:
  `event-storming:methodology --<format>` (pure reference read),
  `event-storming:simulation --discover-bcs` ("applied mechanically against data, not subjectively"),
  `firecrawl:update --check` (report-only), and `kindle-dedrm:manage update` (pure drift check, "no
  mutations"). These do not flip the whole-skill verdict; they are evidence for the
  phase-granularity problem below.

## Rows

<!-- Skill column generated from the filesystem. Rationale lives in the batch artifact, not here. -->

### B01 — [`audit/B01.md`](audit/B01.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/adhd:clarify` | INLINE-ONLY | — |
| [x] | `/adhd:shape` | NO-CHANGE | — |
| [x] | `/ai-briefing:generate` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/architecture:improve` | INLINE-ONLY | — |
| [x] | `/bug-report:write` | INLINE-ONLY | — |
| [x] | `/claude-config:audit` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/claude-config:audit-automation-gaps` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/claude-config:audit-instructions` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/claude-config:audit-permission-grants` | NO-CHANGE | — |
| [x] | `/claude-memory:audit` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/claude-memory:stateless` | INLINE-ONLY | — |

### B02 — [`audit/B02.md`](audit/B02.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/claude-ops:changelog` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/claude-ops:known-issues` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/claude-ops:lanes` | NO-CHANGE | — |
| [x] | `/claude-ops:morning-brief` | NO-CHANGE | — |
| [x] | `/claude-ops:observability` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/claude-ops:plugins` | DISPATCH-OPTIONAL | plugin-agent (`audit`; `disable-model-invocation: true` blocks both delivery paths) |
| [x] | `/code-tidying:audit-comment-residue` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/code-tidying:batch-simplify` | INLINE-ONLY | — |
| [x] | `/code-tidying:tidy` | DISPATCH-OPTIONAL | plugin-agent (`dry-run`: DISPATCH-DEFAULT) |
| [x] | `/codebase-health:audit` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/context7:lookup` | NO-CHANGE | — |
| [x] | `/debugging:debug` | INLINE-ONLY | — |

### B03 — [`audit/B03.md`](audit/B03.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/discovery:blindspot` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/discovery:explore` | DISPATCH-DEFAULT | plugin-agent (`discovery:explorer`) |
| [x] | `/discovery:explore-deep` | NO-CHANGE † | context-fork (existing) |
| [x] | `/discovery:research` | DISPATCH-DEFAULT | plugin-agent (`discovery:researcher`) |
| [x] | `/discovery:research-deep` | INLINE-ONLY † | inline-dispatcher |

† Retirement question **resolved 2026-07-24 (D6), and it split**. `research-deep` is **kept** — its
Tier 1 needs `Workflow` and its multi-topic path needs `Agent`, which errors even inside a true fork,
so its heaviest tier genuinely is not runtime-selectable from a dispatched context. The governing
convention's operative test is *same execution path vs. a second execution path*, not
frontmatter-vs-runtime, so runtime dispatch does not void it. `explore-deep` is **retired
conditionally** — relocating into `plugins/discovery/agents/explorer.md`, but only once that agent
demonstrably reproduces its project-memory loading and its sidecar-on-collision behavior.
`plugins/discovery/agents/` does not exist yet (verified), so unconditional retirement today would
delete working behavior in favor of something unbuilt.
| [x] | `/disk-hygiene:clean` | DISPATCH-OPTIONAL | plugin-agent (audit lane only; `disable-model-invocation: true` blocks both delivery paths) |
| [x] | `/docs-hygiene:audit-derivability` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/docs-hygiene:audit-encapsulation` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/docs-hygiene:audit-noise` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/docs-hygiene:compress` | DISPATCH-OPTIONAL | plugin-agent (`audit` — the skill's own text: "Audit is read-only — no dispatch") |
| [x] | `/docs-hygiene:extract-ssot` | INLINE-ONLY | — |
| [x] | `/docs-hygiene:rename-references` | DISPATCH-OPTIONAL | plugin-agent (all `audit` modes, `preview`, `blocklist`) |

### B04 — [`audit/B04.md`](audit/B04.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/domain-driven-design:curate-language` | NO-CHANGE | — |
| [x] | `/dometrain:grounding` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/dometrain:sync` | NO-CHANGE | — |
| [x] | `/education:explain` | NO-CHANGE | — |
| [x] | `/education:quiz-me` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/education:teach` | INLINE-ONLY | — |
| [x] | `/event-storming:methodology` | INLINE-ONLY | — |
| [x] | `/event-storming:simulation` | DISPATCH-OPTIONAL | plugin-agent (`--discover-bcs`) |
| [x] | `/firecrawl:firecrawl` | NO-CHANGE | — |
| [x] | `/firecrawl:update` | INLINE-ONLY | — |
| [x] | `/github:advise` | DISPATCH-OPTIONAL | plugin-agent (bare invocation — zero mutations) |
| [x] | `/github:audit` | DISPATCH-DEFAULT | plugin-agent |

### B05 — [`audit/B05.md`](audit/B05.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/implementation:implement` | INLINE-ONLY | — |
| [x] | `/implementation:implement-dispatch` | INLINE-ONLY | — |
| [x] | `/kindle-dedrm:manage` | INLINE-ONLY | — |
| [x] | `/knowledge:book-distill` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/knowledge:course-digest` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/knowledge:youtube-digest` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/machine-health:audit` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/mcp-tools:audit` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/naming:name-it-better` | INLINE-ONLY | — |

### B06 — [`audit/B06.md`](audit/B06.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/planning:audit-answers` | INLINE-ONLY | — |
| [x] | `/planning:brainstorm` | DISPATCH-OPTIONAL | plugin-agent (steps 2–3) |
| [x] | `/planning:design` | INLINE-ONLY | — |
| [x] | `/planning:design-handoff` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/planning:devils-advocate` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/planning:draft-goal-condition` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/planning:interview` | INLINE-ONLY | — |
| [x] | `/planning:plan` | INLINE-ONLY | — |
| [x] | `/planning:prd` | INLINE-ONLY | — |
| [x] | `/planning:questionnaire` | NO-CHANGE | — (wrong cell: no dispatch win either way) |
| [x] | `/planning:wayfind` | DISPATCH-OPTIONAL | plugin-agent (`work` mode over the non-interactive frontier) |

### B07 — [`audit/B07.md`](audit/B07.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/playbooks:boris` | NO-CHANGE | — |
| [x] | `/playbooks:fable-5` | INLINE-ONLY | — |
| [x] | `/playbooks:skill-authoring` | NO-CHANGE | — |
| [x] | `/playbooks:update` | NO-CHANGE | — |
| [x] | `/playwright:playwright` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/plugin-quality:audit` | NO-CHANGE | — (already dispatches via `plugin-quality:auditor`) |
| [x] | `/prototype:explore-directions` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/prototype:pressure-test` | DISPATCH-OPTIONAL | plugin-agent |

### B08 — [`audit/B08.md`](audit/B08.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/re-anchor:do-your-research` | INLINE-ONLY | — |
| [x] | `/re-anchor:do-your-research-deep` | NO-CHANGE | — |
| [x] | `/re-anchor:follow-our-standards` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/re-anchor:mind-your-maxims` | INLINE-ONLY | — |
| [x] | `/re-anchor:pick-for-the-problem` | INLINE-ONLY | — |
| [x] | `/re-anchor:point-dont-copy` | DISPATCH-OPTIONAL | plugin-agent (audit half, over a parent-supplied file/diff set) |
| [x] | `/re-anchor:reason-dont-recite` | DISPATCH-OPTIONAL | plugin-agent (audit sweep) |
| [x] | `/re-anchor:recheck-against-upstream` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/re-anchor:recheck-against-upstream-deep` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/re-anchor:reuse-or-replace` | DISPATCH-OPTIONAL | plugin-agent (audit half, over a parent-supplied diff) |
| [x] | `/re-anchor:script-the-deterministic-work` | INLINE-ONLY | — |
| [x] | `/re-anchor:scrutinize-dont-coast` | NO-CHANGE | — |
| [x] | `/re-anchor:sweep-all-disciplines` | NO-CHANGE | — |
| [x] | `/re-anchor:tighten-your-output` | INLINE-ONLY | — |
| [x] | `/re-anchor:use-your-skills` | INLINE-ONLY | — |

### B09 — [`audit/B09.md`](audit/B09.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/repo-fleet-hygiene:audit` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/repo-hygiene:clean` | DISPATCH-OPTIONAL | plugin-agent (`scan`, `stash`, branch audit, every `--dry-run`) |
| [x] | `/review:fanout` | INLINE-ONLY | — |
| [x] | `/review:quality-gate` | DISPATCH-DEFAULT | plugin-agent (mode-specialist, invokes the skill by name) |
| [x] | `/session-flow:clean-stop` | INLINE-ONLY | — |
| [x] | `/session-flow:continue-in-background` | INLINE-ONLY | — |
| [x] | `/session-flow:handoff` | INLINE-ONLY | — |
| [x] | `/session-flow:keep-going` | INLINE-ONLY | — |
| [x] | `/session-flow:orchestrate` | INLINE-ONLY | — |
| [x] | `/session-flow:orient` | DISPATCH-OPTIONAL | history-fork |
| [x] | `/session-flow:reanchor` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/session-flow:reconcile` | INLINE-ONLY | — |
| [x] | `/session-flow:retro` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/session-flow:running-retro` | NO-CHANGE | — (already dispatches) |
| [x] | `/session-flow:workflow` | INLINE-ONLY | — |

### B10 — [`audit/B10.md`](audit/B10.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/skill-quality:check` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/songwriting:co-write` | NO-CHANGE | — |
| [x] | `/songwriting:diagnose` | NO-CHANGE | — |
| [x] | `/songwriting:meter-prosody` | NO-CHANGE | — |
| [x] | `/songwriting:object-writing` | NO-CHANGE | — |
| [x] | `/songwriting:practice` | NO-CHANGE | — |
| [x] | `/songwriting:rhyme` | NO-CHANGE | — |
| [x] | `/songwriting:song-form` | NO-CHANGE | — |
| [x] | `/songwriting:suno` | DISPATCH-OPTIONAL | plugin-agent (delegation candidate) |
| [x] | `/songwriting:workflow` | NO-CHANGE | — |
| [x] | `/source-control:babysit-loop` | NO-CHANGE | — (already dispatches) |
| [x] | `/source-control:babysit-prs` | NO-CHANGE | — (already dispatches) |
| [x] | `/source-control:commit` | NO-CHANGE | — |
| [x] | `/source-control:pull-request` | DISPATCH-OPTIONAL | plugin-agent (`fetch-logs`: DISPATCH-DEFAULT) |
| [x] | `/source-control:resolve-conflicts` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/source-control:worktree` | DISPATCH-OPTIONAL | plugin-agent (`status`, `audit`, `cleanup --dry-run`) |

### B11 — [`audit/B11.md`](audit/B11.md)

| Done | Skill | Verdict | Mechanism |
|---|---|---|---|
| [x] | `/tdd:principles` | NO-CHANGE | — |
| [x] | `/testing:diagnose` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/testing:plan` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/testing:run-e2e` | NO-CHANGE | — (already dispatches) |
| [x] | `/testing:write` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/toolchain:check` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/toolchain:lint` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/verification:confirm` | DISPATCH-DEFAULT | plugin-agent |
| [x] | `/verification:measure` | DISPATCH-DEFAULT | plugin-agent (`background: false` for the `performance` family) |
| [x] | `/visualization:visualize` | INLINE-ONLY | — |
| [x] | `/work-items:attend-queue` | INLINE-ONLY | — |
| [x] | `/work-items:decompose` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/work-items:scan-todos` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/work-items:track` | NO-CHANGE | — |
| [x] | `/work-items:triage` | DISPATCH-OPTIONAL | plugin-agent |
| [x] | `/work-items:work` | INLINE-ONLY | — |
| [x] | `/work-items:work-loop` | INLINE-ONLY | — |

## Open items carried to the plan step

- **`!`-precompute / `allowed-tools` / `${user_config.…}` under `skills:` preload is unverified.**
  Flagged independently by B01, B02, B03, B04, B05, B07, and B09. Nine of B03's twelve skills open
  with a `!` block; for `/discovery:explore` it supplies the project root its own outcome gate cites.
  Mitigated but not closed by preferring runtime `Skill` invocation.
- **Decision 3's "graceful degradation" is false for fresh-context verification disciplines.**
  B03's highest-value finding. `/docs-hygiene:audit-derivability` and `/docs-hygiene:compress` need an
  *uncontaminated* context, not more wall-clock — sequential execution cannot substitute. B06 finds
  the same for `/planning:plan` Step 3 and `/planning:audit-answers` Step 2. For this subset the env
  var is a hard prerequisite.
- **The right unit of dispatch is often a phase, not a skill.** B07's load-bearing lesson, corroborated
  by B02, B04, and B05. `DISPATCH-OPTIONAL` is being stretched to carry "dispatch this phase, keep
  that one"; the vocabulary has no cell for it and 28 rows sit in that bucket.
- **Skills with report-shaped output and no durable artifact.** Dispatching them loses findings rather
  than relocating them: `/planning:devils-advocate`, `/github:audit`, `/codebase-health:audit`,
  `/mcp-tools:audit`, `/repo-fleet-hygiene:audit`, `/testing:plan`, `/docs-hygiene:audit-derivability`,
  `/docs-hygiene:audit-encapsulation`, `/docs-hygiene:audit-noise`, `/work-items:scan-todos`.
- **`disable-model-invocation: true` blocks both dispatch paths** (preload and `Skill` invocation):
  `/claude-ops:lanes`, `/claude-ops:plugins`, `/disk-hygiene:clean`, `/dometrain:sync`,
  `/education:teach`, `/firecrawl:update`, `/playbooks:update`, `/planning:questionnaire`.
- **In-repo prior art to copy rather than reinvent** — `/knowledge:youtube-digest`'s
  `watch-checklist.md` plus its blocking `check-watch-outcomes.js` gate (Decisions 5/6 already built);
  `/verification:confirm`'s assertion-manifest-plus-raw-captures split and `/testing:run-e2e`'s
  evidence-path return (Decision 4 already built); `plugin-quality:auditor`'s bounded-write
  declaration and path-not-paste dispatch prompt.
- **`/discovery:explore-deep` documents its own tool set wrongly.** Line 24 claims it inherits the
  parent's full toolset; a `context: fork` skill is a regular agent type on the narrow background set.
  Its `CLAUDE_CODE_FORK_SUBAGENT` requirement is also attached to the wrong mechanism. Both errors
  overstate the fork's capability, and both need fixing regardless of how the `-deep` question lands.
- **`/discovery:explore` has no coverage-ledger equivalent.** Decision 5 creates
  `research-checklist.md` for research only, but explore maintains an identical numbered gap-list under
  an identical no-Task-tools constraint. Gap in the Brief, not the skill.
- **`/discovery:research` line 148 self-contradicts under dispatch-by-default** — "Subagent returns are
  Tier 3 (synthesis), not corroborators" makes the parent's entire view Tier 3 by the skill's own rule.
  Needs amending to distinguish the artifact from a return read in place of it.
- **`fable-5`'s `context/orchestration.md` encodes competing criteria** — three delegation triggers and
  four stay-inline overrides sharper than anything here. Reconcile deliberately rather than let them
  drift.
