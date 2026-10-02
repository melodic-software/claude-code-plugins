## Brief

### TLDR

- One `docs/upstream/` record for the claude.dev post "What a task costs on Opus 5.5" (2026-09-25): each adopted row points at the official docs section that states the mechanism, and every post-vs-docs conflict is logged with a recheck trigger.
- Small repo edits on this branch: pointers in place of restated vendor facts (prompt caching, task cost, effort guidance, `/doctor prompt-audit`), one path-scoped writing rule for cost claims, an audit check that every shipped agent sets `model:`, and the research gate's row 7 amendment.
- `claude-ops:observability` gains a same-task comparison (tokens by type, split by model and effort), reconciled against the open OTEL undercount bug.
- Planner-scopes / Sonnet-implements (Q20) ships on this branch (Q41, 2026-10-01): a per-phase `Model` column in the plan's routing table and a Sonnet implementer agent at medium effort. Parallel-by-default dispatch (Q35) stays a tracked follow-up.
- The 12 `audit-instructions` rows that overlap `/doctor prompt-audit` keep their text, and the upstream record lists the overlap (Q42, reconfirmed at plan approval 2026-10-01).
- Every item in a file another session owns has a confirmed doer: the owner took it, or released it to this branch (Q46, 2026-10-01).

### Goal

Bring the repository in line with what the official Anthropic docs say about the cost levers the post discusses (effort, model choice, prompt caching, subagent routing, measurement), so that repo guidance points at the current docs instead of restating vendor figures, records where the post and the docs disagree, and adds only the tooling that the built-in Claude Code features do not already cover.

### Constraints

- C1: the interview ran on the page surface, port 42356. (confirmed)
- C2: every repo-facing claim from the post is vendor-documented MEDIUM; none is independently settled. (inherited, research rulings)
- C3: work lands as a draft PR titled in Conventional Commits form, flipped to ready when done. (inherited, AGENTS.md)
- C5: Building With Claude Sonnet 5.5 owns `prompts/loops/loop-lane-prompts.md` and the boris reference files; Prompting Sonnet 5.5 owns the `docs/plugin-philosophy.md` tiers, agent effort pins, verification skills and the Sonnet 5.5 chapter. This branch messages the owner rather than editing. (inherited, peer relay; confirmation is Q46)
- C6: Prompting Sonnet 5.5 owns the docpage-digest SKILL.md and its profile and verification files, and `criteria.md` row I17-b; in `docs/upstream/` and the digest queue this branch adds only this post's own entry. (confirmed)
- C7: mechanism decisions (which hook, env var, exact edit) are made at `/planning:plan`. (confirmed, Q2)
- C8: every interview question quoted and linked its source. (confirmed)
- C9: prefer native built-in Claude Code features; skills wrap or point to them, never duplicate. (confirmed)
- C10, C11: alternatives never repeat the recommendation, and stay current after every revision. (confirmed / inherited)
- Q3: billing is a Claude subscription; no API key anywhere.
- Q4: run no local measurements; act on the official docs as written; record every conflict between two official sources with a recheck trigger.

Decisions (register rows; full text in `.work/opus-5-5-task-cost-interview/interview-checklist.md`):

- Q1: a third `docs/upstream/` record for this post, then implement the adopted rows (shape and delivery split: Q43).
- Q5: keep `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` declined; repo text follows the docs' model order, not the post's.
- Q6: amend research outcome-gate row 7 so vendor-only MEDIUM claims listed as gaps pass, after checking the row's other callers.
- Q7: cost measurement reconciles `api_request` totals against `claude_code.cost.usage` and compares token counts ([anthropics/claude-code#98193](https://github.com/anthropics/claude-code/issues/98193)).
- Q8: name `/doctor prompt-audit` in audit-instructions, the audit-pass doctor handoff and `bundled-claude-api.md` rows 13 and 16 (scope beyond those: Q48).
- Q9: hard-problems effort follows the docs' per-model table; repo text points there.
- Q10-Q12: docpage-digest fixes (blog-apparatus tag category, exact-byte write route, pin freeze names the parent), sent to Prompting Sonnet 5.5.
- Q13: anything cited from the post carries canonical link, publish date, date last checked and recheck trigger only.
- Q14: no `Plan.md` override; the built-in Plan agent and the user's per-spawn routing rule stay; the record states how Plan picks its model.
- Q15: no new cache chapter; one pointer to the Claude Code prompt-caching page in `prompt-caching.md`'s session-side section; repo text follows the docs on the MCP trigger, effort exception list and cold `/compact`.
- Q17, Q18: audit-instructions keeps its report-only catalog beside `/doctor prompt-audit`; which prompt-audit gap rows and the post's four ritual patterns to adopt is decided at planning after a row-by-row read (overlap exception: Q42).
- Q19: the two literal "default high" effort lines become pointers to model-config; sent to Building With Claude Sonnet 5.5.
- Q20: follow the docs' split (Sonnet 5.5 for well-scoped coding, Opus for complex work); planning and implementation skills change so the planner scopes and Sonnet implements; the post's "code edits on Opus" is logged as a conflict (timing and pin: Q41).
- Q21: no loop cadence change; the record logs the subscription TTL facts and the `--bg` / routine TTL gap.
- Q22: extend `claude-ops:observability` with a two-session comparison, tokens by type (cache writes reported as their own type) split by model and effort; no new plugin or skill.
- Q24: no new routing rule; an audit check flags any shipped agent definition with no `model:`.
- Q25: on the next edit of a model-routing surface, link the docs' opusplan section and agent-team cost sentence, no restated figure.
- Q26: a closing report is not proof of done; already covered; the record notes the guide's continuation cap as not stated in the repo.
- Q28: one path-scoped writing rule for cost claims, worded to the live costs doc; no audit check.
- Q29: the post's figures stay out of repo guidance; only the upstream record lists them, as vendor-reported (wording under review: Q38).
- Q30: the post's effort guidance graduates as pointers to the docs sections only.
- Q32: no new audit rows; the thinking-off row names the docs' current model list; the I17-b update went to its owner.
- Q33: low-severity bundle: observer default unchanged; keep v2.1.242 and log the missing changelog heading; keep the dated count of 13; check USD anchors and the listing budget for records; boris finding sent to its owner.
- Q34: two related posts queued for later digest, standfirsts as vendor claims, picker text as a cited vendor-claimed quote (queue ownership: Q39).
- Q35: parallel-by-default dispatch as its own effort after Q20: subagents for focused phases, agent teams only where the user enabled them and workers must coordinate; the one-worker pilot before a fan-out wider than about 4 stays.
- Q36: no repo-authored cost explanation; link the costs doc's "Why usage climbs in a long session" from the Q15 pointer and `/planning:draft-goal-condition`.
- Q37: Sonnet 5.5 chapter requested from its owner (already in that session's PR); `opus-5-5.md` unchanged.

### Acceptance criteria

Derived from the accepted commitments at wrap-up; the interview did not ask the acceptance-criteria question, so confirm these at the `/planning:plan` approval gate.

- `docs/upstream/` has one record for this post whose every adopted, covered, not-adopted and gap row links the official docs section it rests on with a date checked and a recheck trigger, and whose conflict rows name both official sources.
- No repo file outside that record and this topic's own planning slice restates a figure, percentage or price from the post (`git grep` for the post's figures outside `docs/upstream/`, `docs/topics/` and `.work/` returns nothing).
- `grep -rn 'doctor prompt-audit'` outside `.work/` finds it in the audit-instructions Boundary, the audit-pass doctor handoff and `bundled-claude-api.md`.
- `plugins/playbooks/reference/prompt-caching.md`'s session-side section links the Claude Code prompt-caching page and the costs doc section, and `/planning:draft-goal-condition` links the costs doc section.
- A path-scoped rule file for cost claims exists and its `paths:` globs resolve (`/instruction-placement:check` passes).
- An audit check reports 0 findings for shipped agents missing `model:` across `plugins/*/agents/*.md`.
- Research outcome-gate row 7 passes an artifact whose every claim is MEDIUM and listed as a gap, and the Sonnet 5.5 research re-grades under it.
- `claude-ops:observability` produces a two-session comparison with tokens by type split by model and effort, reconciles cost totals as in Q7, and its tests pass.
- A work item exists for the Q35 parallel default, filed as a sub-issue of this branch's parent issue and linked from the record.
- A plan whose routing table assigns `sonnet` to a phase makes implement-dispatch spawn `implementation:scoped-implementer` (`model: sonnet`, `effort: medium`); an unrouted phase spawns `implementation:implementer` (`opus`); an eval case covers both.
- The upstream record lists the 12 `audit-instructions` rows that overlap `/doctor prompt-audit` with the complementary verdict, no criteria row changes for Q42, and the pre-scan tests still pass.
- The draft PR's `ci-status` check is green.

Amended 2026-10-01 at the plan gate: Q41 moved Q20 in scope; Q42 retired the overlap exception; the effort-pin owner (Prompting Sonnet 5.5) chose a separate Sonnet implementer agent at medium and released it to this branch.

### Captured assumptions

- Q3 billing path: read from the dictated "cloud subscription" as a Claude subscription; the read-back was posted but never confirmed. Revisit if the user corrects it (Q21 rests on it).
- Q20 extension (planner scopes, Sonnet implements): a read-back of a free-text question, not a ticked option. Revisit at planning with Q41.
- Q1 commitments were accepted without being ticked. Revisit with Q43.
- Q36: the user accepted Q27 (a repo cost paragraph) after it was replaced, then Q36 (link only); Q36 is taken as the decision. Revisit if the user meant the paragraph.
- 76 page commitments were accepted but not individually ticked. Each stands as a named risk: the commitment is assumed to hold, revisit if planning finds it wrong. The full list is in `.work/opus-5-5-task-cost-interview/interview-surface/brief-export.md` under "Captured assumptions".
- The relayed cross-session rules (Q38) are not applied to the decisions above. Revisit if the user confirms them; Q1, Q13, Q20 and Q29 would be re-worded.

### Out-of-scope

- Q16, Q23, Q27, Q31: withdrawn and replaced by Q22, Q35, Q36 and Q37.
- Local measurement runs (Q4).
- Building the Q35 change (follow-up effort). Q20 moved in scope at the 2026-10-01 plan gate (Q41).
- Editing files owned by other sessions (C5, C6).

### Deferred questions

All eleven are resolved as of 2026-10-01: the seven USER-RESERVED ones by the user (ledger rows Q38, Q39, Q41, Q42, Q43, Q45, Q46), the four plan-owned ones in the Plan's Decisions table. The original deferral text is kept below.

- Q38: Do the relayed rules (links only, main docs over blog posts, and the rest) apply to this interview's decisions? Recommendation: apply them. Defer until the `/planning:plan` approval gate; **arbiter: USER-RESERVED**
- Q39: Do Q5's `claude-code.md` line-75 update and Q34's two queued posts go to their owner session, per C6? Recommendation: yes; this record carries both as rows. Defer until the `/planning:plan` approval gate; **arbiter: USER-RESERVED**
- Q40: Does the observability comparison mention the post's "three or four tasks"? Recommendation: link the post section, state no count. Defer until planning; **arbiter: /planning:plan**
- Q41: Does the Q20 planner-scopes / Sonnet-implements change ship here or as its own tracked effort, and does the implementer's Opus pin stay? Recommendation: own effort before Q35; no pin change here. Defer until the `/planning:plan` approval gate; **arbiter: USER-RESERVED**
- Q42: Is Q17's retained overlap with `/doctor prompt-audit` a time-limited exception to C9? Recommendation: yes, ending at planning's row-by-row read. Defer until the `/planning:plan` approval gate; **arbiter: USER-RESERVED**
- Q43: Does the record file a work item per adopted row (precedent) or does this branch implement the small rows? Recommendation: small rows here; Q20, Q35 and Q22 get work items. Defer until the `/planning:plan` approval gate; **arbiter: USER-RESERVED**
- Q44: Three consistency fixes (Q4's leftover commitment, both links in one `prompt-caching.md` pointer line, Q13's stamp for post citations only). Recommendation: fix all three. Defer until planning; **arbiter: /planning:plan**
- Q45: One draft PR, and what it closes? Recommendation: one draft PR, a commit per area, closing a parent issue with the follow-ups as sub-issues. Defer until the `/planning:plan` approval gate; **arbiter: USER-RESERVED**
- Q46: Confirm the cross-session file ownership in C5? Recommendation: confirm as stated. Defer until the `/planning:plan` approval gate; **arbiter: USER-RESERVED**
- Q47: Record the uncovered handoff items (cache hooks, cache-miss triage, `/usage` reference, team reporting, startup payload, batching and plan claims, research gaps G1-G5) in the record with nothing built? Recommendation: yes. Defer until planning; **arbiter: /planning:plan**
- Q48: Does the prompt-audit spec also name `/doctor prompt-audit`, with ADR-0028 unchanged? Recommendation: yes. Defer until planning; **arbiter: /planning:plan**

## Plan

Base: `origin/main` at `63cc66ad2` (fast-forwarded 2026-10-01). All line numbers were re-derived on that base (`.work/opus-5-5-task-cost/regrounding-main.md`).

### Goal

Land the Brief as one draft PR:
- an upstream record for the post;
- pointer edits in place of restated vendor facts;
- the research-gate clarification;
- the observability `compare` action;
- per-phase Sonnet routing (Q20);
- the remaining `/doctor prompt-audit` naming.

Every row rests on an official docs section (Q38 rules).

### Standards grounding

- `.claude/rules/skill-bodies-state-current-rules.md`: Claim / Basis / As of / Recheck trigger for any volatile specific a skill or agent body restates. This covers both implementer agents, implement-dispatch, plan-template and the observability SKILL.md caveat.
- `.claude/rules/pr-body-contract.md`: the closing keyword and four sections.
- `docs/conventions/upstream-drift/README.md`: the four-part record shape the upstream record's row schema cites.
- The skill line cap: `check-skill.sh:513,924` fails at 500 lines. audit-instructions `SKILL.md` and audit-pass `SKILL.md` are both at 497, so edits there replace text in place and add no lines.
- `plugins/playbooks/reference/model-adaptation/AGENTS.md`: not touched (Q37).

### Sequencing constraints (cross-session)

- **Gate S1:** the Prompting Sonnet 5.5 session's merge reaches `origin/main`. That session is reworking #5746 (merged 22:10Z from another machine's issue worker), and its resolution changes I8-c scope, the plugin-philosophy "Model tiers" table and the shape of `anthropic-docs-queue.md`. It will message this session when its merge commit is on its branch. Phase 5 step 8, Phase 6 and Phase 7 step 1 wait for that merge, followed by a fresh `git merge origin/main` here.
- Building With Claude Sonnet 5.5: #5676 is on main. #5759 (the boris Q19 and Q33 rows, the foundations §4 amendment, and superseded notes on tips 67 and 79) merged as `6b0802bdd` on 2026-10-01; the record marks those rows landed and links it. Merge `origin/main` again before Phase 1 so the base includes it.
- Items owners hold, which this branch records but does not do: I17-b; the docpage-digest Q10-Q12; the Sonnet 5.5 chapter; the #5678 model-tier points (Prompting); boris (Building, #5759).

### Phase 1: Tracker and upstream record draft [DONE]

Model: opus (judgment over 48 ledger rows; remote writes).

1. Search before create: `gh issue list --repo melodic-software/claude-code-plugins --state all --search "Opus 5.5 task cost in:title"`. Reuse a match as the parent. Otherwise create:
   - a parent issue, "docs(upstream): answer 'What a task costs on Opus 5.5'";
   - a Q35 sub-issue (parallel-by-default dispatch);

   Link each sub-issue to the parent: `gh api repos/melodic-software/claude-code-plugins/issues/<child> --jq .id`, then `gh api -X POST repos/melodic-software/claude-code-plugins/issues/<parent>/sub_issues -F sub_issue_id=<id>`. Repository: melodic-software only (Q38 rule 3).
2. Write `docs/upstream/opus-5-5-task-cost.md` in the header shape of `docs/upstream/opus-5-5-usage-guide.md`: H1, Contents, Status, Source and verification (post URL `https://claude.dev/blog/what-a-task-costs-on-opus-5-5/`, published 2026-09-25, read date, recheck trigger; the post is a correlate only), Row schema, one section per post section, `## Conflicts`, `## Decisions and follow-ups`. Row columns: `Post item | Official docs section | Ours | Verdict | Checked | Recheck trigger`. Each adopted row names the docs section it trusts (Q44, Q4 fix). The record carries:
   - every adopted, covered, not-adopted and gap row from ledger Q1-Q48;
   - Q24 as COVERED (`scripts/validate-plugin-contracts.mjs`, #4568);
   - Q8 as largely COVERED by #5387 (`audit-instructions/SKILL.md:115-129`, `reference/native-doctor.md`);
   - the Q47 uncovered items (cache hooks, cache-miss triage, `/usage` reference, team reporting, startup payload, batching and plan claims, research gaps G1-G5), each with a disposition and nothing built;
   - the post's figures, here only and labelled vendor-reported (Q29);
   - the evals USD anchors (`plugins/evals/skills/plugin-eval/SKILL.md:139-146`), noted as measured before 5.5 (Q33);
   - stated deviations:
     - Q43 implements rows in the record's own PR, against `claudedevs-cost-performance.md:19`;
     - Q20 keeps `opus` for unrouted dispatch, against costs#choose-the-right-model; the reason is fail-safe behavior for lanes with no plan, plus provider alias drift;
   - owner rows with their doer and PR;
   - the Q42 outcome from the approval gate.
3. Q39(a): `docs/upstream/claude-code.md:75` keeps `_FORCE` declined, and notes that `CLAUDE_CODE_SUBAGENT_MODEL` alone does not move built-in Plan or Explore (sub-agents#choose-a-model).
4. Resolve every cited docs anchor with `curl -s https://code.claude.com/docs/en/<page>.md | grep '^#'` and stamp the check date.
5. Commit `docs/topics/opus-5-5-task-cost/` with this phase.

**Sanity Check:**
- `gh issue view <parent> --json state --jq .state` prints `OPEN`, and `gh api repos/melodic-software/claude-code-plugins/issues/<parent>/sub_issues --jq 'length'` is ≥1.
- The per-row link check prints nothing:
  `awk -F'|' '/^## /{sec=$0} /^\|/ && !/^\|[ -]*\|/ && !/Post item|Post says/ { if (sec ~ /Conflicts/) { n=gsub(/https?:\/\/(code|platform)\.claude\.com\/docs/,"&"); if (n<2) print "conflict:" NR } else if (sec !~ /Decisions and follow-ups/ && $3 !~ /https?:\/\/(code|platform)\.claude\.com\/docs/) print "row:" NR }' docs/upstream/opus-5-5-task-cost.md`
- The Q29 grep prints nothing:
  `git grep -n -I -E '40% (less|cheaper)|25% further|\$0\.75|about ten turns|retry costs more|No other setting moves|\$13 per|\$11\.20|\$1\.62|\$0\.99|\$3\.50|\$242|\$0\.025|2\.8M|31% less|44 tickets|further 9%' -- ':!docs/upstream' ':!docs/topics' ':!.work'`
  The topic slice ships in the PR and quotes the patterns, hence its exclusion.

### Phase 5: Per-phase Sonnet routing (Q20) [DONE except step 9, which waits on Gate S1]

Runs second, so Phases 2 and 3 can dispatch through the route it creates. Model: opus (cross-plugin contract change).

1. Consumer check first: `git grep -n -E 'implementation:implementer|Per-phase routing table|route a phase \*\*upward\*\*|Phase \| Surface'`. Update each hit or clear it with a reason in the commit message. Known hits on `63cc66ad2`:
   - implement-dispatch `SKILL.md:88,92-106,161,171,195`;
   - `plugins/planning/skills/plan/templates/plan-md-anatomy.md:29`;
   - `plugins/implementation/README.md:20`, whose agents table gains a row;
   - `plugins/work-items/skills/work/SKILL.md:213`, the fix worker;
   - implement-dispatch `evals.json:99,103`.
2. `plugins/planning/skills/plan/context/plan-template.md:263-272`: add a `Model` column (`sonnet` | `opus` | `frontier`). `sonnet` requires a closed scope fence, binary acceptance criteria, no open design decision, no cross-module contract change, and not a security-surface class. `opus` covers architectural work, per-file judgment and multi-step reasoning (costs#choose-the-right-model). `frontier` is unchanged (loop-lane README :372). Update Step 9 at `:389`. Add a one-line Step 4.5 pointer in the plan `SKILL.md`. Q25: link model-config#opusplan-model-setting and costs#agent-team-token-costs, with no figures.
3. New `plugins/implementation/agents/scoped-implementer.md` (`model: sonnet`, `effort: medium`). Its worker contract is copied inline from `implementer.md`: the scope fence, STOP rules and return shape stay in the agent body, because a reference file depends on a Read the worker may skip (stress-test #6). Copy `implementer.md`'s `skills:` and `tools:`. Add a Claim / Basis / As of / Recheck record for its pins:
   - Basis: the effort-pin owner's ruling of 2026-10-01; the model-config effort rows; phase-verifier already at `effort: medium` (c79aa290c).
   - The `availableModels` substitution keeps medium effort on a stronger model (sub-agents#choose-a-model).
   - Recheck when the Agent tool gains a per-spawn effort parameter.
4. Red first: a new `plugins/implementation/scripts/agent-contract-sync.test.sh` fails when the text between `<!-- contract:begin -->` and `<!-- contract:end -->` markers differs between `implementer.md` and `scoped-implementer.md`, or when their `skills:` or `tools:` lines differ.
5. `plugins/implementation/agents/implementer.md:82-86`: the frontmatter is the default for unrouted or complex phases, and a plan-routed `sonnet` phase goes to `scoped-implementer`. Wrap the shared contract in the markers.
6. implement-dispatch `SKILL.md:88,92-106,195`. Routing:
   - A row marked `sonnet` spawns `implementation:scoped-implementer` with an explicit per-invocation `model: sonnet`. The explicit value matters: a caller rule like "pass `model: opus` on every spawn" would otherwise override the frontmatter (stress-test #3).
   - Before routing to `sonnet`, a dispatch-time provider check: if `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX` or `CLAUDE_CODE_USE_FOUNDRY` is set and `ANTHROPIC_DEFAULT_SONNET_MODEL` is unset, spawn `implementation:implementer` instead (model-config#model-aliases). The orchestrator reads these with `printenv`.
   - No row means `implementation:implementer`; a security class means frontier.
   - The upward-only rule for `model` on `implementer` stays. Add a sentence that downward routing happens only by spawning `scoped-implementer`.
   - Refresh the stamp at `:105`.
   - Red first: an evals.json case asserting each of the three routes, including the explicit `model: sonnet` value.
7. `plugins/work-items/skills/work/SKILL.md:213`: reword "same tier as the original implementation" to "the strong tier, never below the original" (stress-test #10).
8. `docs/conventions/loop-lane/README.md:370-374`, tier roles: strong is the default for unrouted or complex work; fast adds plan-routed well-scoped phases. `prompts/loops/loop-lane-prompts.md:357-358,378-385` (released by Building) get the same qualification.
9. After Gate S1: `docs/plugin-philosophy.md`, routing clauses only, on the merged text (on `63cc66ad2`: "one tier" :1105, dispatch-site :1195, "raise the pair together" :1198; re-grep after the merge). The verdict rule, the effort clauses and Pinned agents stay untouched.
10. Version bumps and CHANGELOG entries for planning, implementation and work-items.

**Sanity Check:**
- `grep -c -E '^(model: sonnet|effort: medium)$' plugins/implementation/agents/scoped-implementer.md` prints `2`.
- `bash plugins/implementation/scripts/agent-contract-sync.test.sh` exits 0.
- `bash scripts/validate-plugin-contracts.test.sh` exits 0.
- `jq '[.evals[] | tostring | select(test("scoped-implementer") and test("model: sonnet") and test("implementation:implementer"))] | length' plugins/implementation/skills/implement-dispatch/evals/evals.json` ≥1.
- `git grep -n 'route a phase \*\*upward\*\*' plugins/implementation` still hits. `git grep -c 'CLAUDE_CODE_USE_BEDROCK' plugins/implementation/skills/implement-dispatch/SKILL.md` ≥1.
- `grep -c -E '^\| .*\| (sonnet|opus|frontier) \|' plugins/planning/skills/plan/context/plan-template.md` ≥1.
- `bash plugins/skill-quality/scripts/check-skill.sh plugins/implementation/skills plugins/planning/skills plugins/work-items/skills` exits 0.
- Changelog parity, one mode per call: `bash scripts/check-changelog-parity.sh --check`, `bash scripts/check-changelog-parity.sh --check-bump origin/main`, `bash scripts/check-changelog-parity.sh --check-order` and `bash scripts/check-changelog-parity.sh --check-preserved origin/main` each exit 0.

### Phase 2: Pointer edits and cost-claims rule [TODO]

Model: sonnet, dispatched through `scoped-implementer`. This is the first real use of the Phase 5 route. Files:

| File | Change | Ledger |
|---|---|---|
| `plugins/playbooks/reference/prompt-caching.md` (after :117) | One line: the Claude Code prompt-caching page and costs#why-usage-climbs-in-a-long-session, with check date and recheck trigger | Q15, Q36, Q44 |
| `plugins/planning/skills/draft-goal-condition/SKILL.md` Gotchas (:135-140) | One bullet linking costs#why-usage-climbs-in-a-long-session | Q36 |
| `plugins/claude-config/skills/audit-instructions/SKILL.md` claude-api Routing paragraph (:100-106) | Reword in place, no added line: `/doctor prompt-audit` for Claude Code configuration, `/claude-api prompt-audit` for application-code prompts | Q8 |
| `plugins/claude-config/skills/audit-pass/SKILL.md:282-289` | Reword in place, no added line: name `/doctor prompt-audit` with the commands link | Q8 |
| `plugins/claude-config/skills/audit-pass/reference/doctor-handoff.md` (after :15) | One sentence naming `/doctor prompt-audit`, report-first, handed off the same way | Q8 |
| `plugins/claude-config/skills/audit-instructions/reference/bundled-claude-api.md` :13, :16 | Qualify :13 to the `/claude-api` door; add a `/doctor prompt-audit` row; re-stamp :16, whose trigger fired at 2.1.283 | Q8 |
| `docs/specs/prompt-audit-skills-2026-09.md` Follow-ups (:628) | One line: `/doctor prompt-audit` covers Claude Code configuration; a rerun over `plugins/*/skills/` still uses `/claude-api prompt-audit`. ADR-0028 unchanged | Q48 |
| `.claude/rules/cost-claims.md` (new) | Path-scoped rule: cost claims point at costs (Track your costs, `/usage`) and pricing, never at prices or per-task figures; `docs/upstream/` records may list vendor figures labelled vendor-reported. `paths:` `plugins/*/skills/**`, `plugins/*/agents/**`, `plugins/*/reference/**`, `docs/**/*.md`, `prompts/**` | Q28 |
| `plugins/instruction-placement/scripts/render-index.sh` + `render-index.test.sh` | Q45 (2026-10-01): fix the generator in this PR. Red first: a test fixture tree with a `.claude/rules/` file under an `evals/fixtures/` path must not appear in `render` output. Then exclude eval-fixture trees (the two leaking files sit under `plugins/claude-ops/skills/changelog/evals/fixtures/consumer-repo/`, from 681789d59) | Q45 |
| `AGENTS.md` generated rules table | Regenerate: `bash plugins/instruction-placement/scripts/render-index.sh write --file AGENTS.md`, which adds the cost-claims row and no fixture rows | Q28 |

Version bumps and CHANGELOG entries for playbooks, planning, claude-config and instruction-placement.

**Sanity Check:**
- `git grep -c 'doctor prompt-audit' -- plugins/claude-config/skills/audit-pass plugins/claude-config/skills/audit-instructions/reference/bundled-claude-api.md docs/specs/prompt-audit-skills-2026-09.md` is ≥1 in each of the four targets: audit-pass `SKILL.md` or `doctor-handoff.md`, `bundled-claude-api.md`, and the spec. These are files that have no hit on `63cc66ad2`.
- `wc -l < plugins/claude-config/skills/audit-instructions/SKILL.md` and `wc -l < plugins/claude-config/skills/audit-pass/SKILL.md` each print ≤499.
- `grep -c 'costs#why-usage-climbs-in-a-long-session'` prints 1 for each of `plugins/playbooks/reference/prompt-caching.md` and `plugins/planning/skills/draft-goal-condition/SKILL.md`.
- `bash plugins/instruction-placement/scripts/render-index.test.sh` exits 0, including the new fixture-exclusion case.
- `bash plugins/instruction-placement/scripts/render-index.sh check --file AGENTS.md --root .` prints `IN-SYNC`; `grep -c 'cost-claims.md' AGENTS.md` prints 1; `grep -c 'evals/fixtures' AGENTS.md` prints 0.
- `git diff --stat origin/main -- docs/decisions/` prints nothing.
- Changelog parity: the four single-mode calls from Phase 5 each exit 0.

### Phase 3: Research outcome-gate row 7 [TODO]

Model: sonnet, through `scoped-implementer`.

1. Consumer check: `git grep -n -E 'row 7|4, 7 and 12|criteria 4, 7|HIGH confidence|until every claim' plugins/discovery`. Update each hit or clear it with a reason. Known hits on `63cc66ad2`:
   - `agents/researcher.md:271,301`
   - `agents/research-verifier.md:19,37`
   - `skills/research/context/phases.md:74`
   - `reference/parent-contract.md:482`
   - `skills/research-deep/SKILL.md:97`
   - `context/dispatch.md:73`
   - `context/gotchas.md:42`
   - `skills/research/evals/evals.json:131,316,318`

   `discipline.md:298` already counts MEDIUM as a Gap; leave it unchanged.
2. `plugins/discovery/skills/research/SKILL.md:78` row 7 becomes: "Every accepted claim is HIGH confidence. A claim labelled MEDIUM or LOW and listed in the Gaps section is not accepted, so an artifact whose every claim is so labelled and listed passes". Follow-up: "Iterate to HIGH or list as a Gap". Mirror one sentence in `research-verifier.md` near :37. Avoid any text matching the `assert_absent` stale-count pattern in `contract.test.sh:535-563` (for example "rows 4 and 7").
3. Red first: a `contract.test.sh` assertion that row 7 contains "listed in the Gaps section".
4. Re-grade `.work/opus-5-5-task-cost-research/sonnet-5-5-guide/` by dispatching `discovery:research-verifier`.
5. Discovery version bump and CHANGELOG entry.

**Sanity Check:**
- `bash plugins/discovery/scripts/contract.test.sh` exits 0, including the new assertion.
- The verifier's verdict line for the sonnet-5-5-guide artifact reports row 7 PASS.
- Changelog parity: the four single-mode calls each exit 0.

### Phase 4: Observability `compare` action (TDD) [DONE]

Model: opus (new SQL and reconciliation logic). Runs in parallel with Phase 5. Design in `design/design-resolution.md`.

1. Red first: `plugins/claude-ops/skills/observability/scripts/session-compare.test.sh`, in the `hook-latency.test.sh` pattern. Cases:
   - usage errors: one id, identical ids, an id containing `'`;
   - missing store;
   - `cacheCreation` as its own type;
   - effort `high` vs `none`;
   - per-type totals;
   - the three reconciliation statuses: `events short` naming #98193, `match`, `events exceed metric`;
   - attribute typing: `intValue`, `doubleValue`, `asInt`, `asDouble`;
   - an absent session id;
   - a metric with `aggregationTemporality` other than 1 (delta) exits 2 with "cannot reconcile: cumulative metrics" (stress-test #4, monitoring-usage `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE`);
   - the context line (Q40): monitoring-usage docs link first, the post's "Measure it yourself" section as a correlate, no task count.
2. `otel/session-compare.sql` reads `effort` and `aggregationTemporality` from raw attributes; `cc-otel.sql` is unchanged. `scripts/session-compare.sh` guards ids with `^[A-Za-z0-9._-]+$` and exits 0 rendered, 2 cannot evaluate.
3. `SKILL.md`: argument-hint, action table row, dispatch block, error list, description trigger, and a Claim / Basis / As of / Recheck record for the #98193 caveat.
4. `evals/evals.json` id 6. claude-ops version bump and CHANGELOG entry.

**Sanity Check:**
- `bash plugins/claude-ops/skills/observability/scripts/session-compare.test.sh` exits 0 with no skips (duckdb 1.5.5 is present on this machine).
- These suites still exit 0 (OBS = `plugins/claude-ops/skills/observability`): `OBS/claude-observability.test.sh`, `OBS/scripts/hook-latency.test.sh`, `OBS/scripts/probe-observability-state.test.sh`, `OBS/scripts/report-path.test.sh`, `OBS/otel/net-probe.test.sh`, `OBS/otel/prune-otel-store.test.sh` and `OBS/otel/clean.test.sh`.
- `git diff --quiet origin/main -- plugins/claude-ops/skills/observability/otel/cc-otel.sql` exits 0.
- Changelog parity: the four single-mode calls each exit 0.

### Phase 6: Thinking-off row and the Q42 outcome [TODO]

Model: opus. Starts after Gate S1, because `criteria.md` and the I8-c scope are being reworked on the Prompting branch.

1. `git merge origin/main`, then re-derive the line numbers below.
2. Q32: I17-a (on `63cc66ad2`: `criteria.md:1118-1143`, plus :1062-1066, :1128, :1133; "On Fable 5 it has no effect" at :1122) replaces the named model with a pointer to model-config#extended-thinking and is re-stamped. I17-b is not touched.
3. Q42, per the approval-gate reply (see Displaced answers):
   - **(recommended) keep:** the overlapping rows keep their text, the record lists the 12 rows and states the complementary verdict (`reference/native-doctor.md` §"Why the verdict is complementary", #5387), and no criteria row changes;
   - **(original answer) point:** the 12 OVERLAP rows (I1, I5, I8, I8-c, I8-e, I9, I10, I20, I25, I26, I28, I31) get pointer wording; scanner ids and patterns stay; the `sonnet-5-5` widening bullets survive as the merged text has them; I8-e, I8-f and I29 adopt Anthropic's guide; I32 stays with a recheck trigger. The bundled guide is first extracted from the installed binary (as `RESEARCH-commands.md` did), falling back to the raw GitHub copy.
4. claude-config version bump and CHANGELOG entry.

**Sanity Check:**
- `git grep -n 'On Fable 5 it has no effect' plugins/claude-config` prints nothing.
- An awk range from `I17-b` to the next row id shows no changed line inside I17-b in `git diff origin/main -- plugins/claude-config/skills/audit-instructions/reference/criteria.md`.
- The audit-instructions scanner tests (`instruction-scan`, `emit-findings`, `finding-ids` under `plugins/claude-config/skills/audit-instructions/scripts/`) each exit 0.
- Under "point" only: `git diff origin/main -- …/criteria.md | grep -c '^+.*doctor prompt-audit'` ≥12.
- Changelog parity: the four single-mode calls each exit 0.

### Phase 7: Queue entries, record finalization, draft PR [TODO]

Model: opus (main session; remote writes).

1. After Gate S1: add "Spending your effort" and "Prompt caching is everything" (Q34) to `plugins/knowledge/skills/docpage-digest/context/anthropic-docs-queue.md` in the merged file's shape. Knowledge version bump and CHANGELOG entry.
2. Fill in the record's links: the parent issue, the sub-issues, #5759, the Prompting merge PR.
3. Open a draft PR titled `docs(upstream): answer "What a task costs on Opus 5.5" with routing, observability and pointer updates`. Its body follows `.claude/rules/pr-body-contract.md` and opens with `Closes #<parent>`.
4. Tick digest Phase 5 in `.work/claude-dev-blog-what-a-task-cos-155f49d4/docpage-digest-checklist.md`.

**Sanity Check:**
- `gh pr view --json isDraft --jq .isDraft` prints `true`, and `gh pr view --json body --jq .body | head -1` matches `^Closes #[0-9]+`.
- `gh pr checks --json name,state --jq '.[] | select(.name=="ci-status") | .state'` prints `SUCCESS` after CI completes.
- Changelog parity: the four single-mode calls each exit 0.

### Test strategy

TDD where there is code:
- Phase 4: the red `session-compare.test.sh` first.
- Phase 3: the red `contract.test.sh` assertion first.
- Phase 5: the red `agent-contract-sync.test.sh` and implement-dispatch eval first.

Test boundaries:
- the `session-compare.sh` CLI (new);
- `contract.test.sh` (existing);
- `agent-contract-sync.test.sh` (new, guards the inline copy);
- `scripts/validate-plugin-contracts.mjs` (existing);
- implement-dispatch evals.json (existing, new case);
- the audit-instructions scanner tests (existing).

Docs-only edits verify by grep. No local cost measurement runs (Q4).

### Files affected

Created:
- `docs/upstream/opus-5-5-task-cost.md`
- `.claude/rules/cost-claims.md`
- `plugins/implementation/agents/scoped-implementer.md`
- `plugins/implementation/scripts/agent-contract-sync.test.sh`
- `plugins/claude-ops/skills/observability/otel/session-compare.sql`
- `plugins/claude-ops/skills/observability/scripts/session-compare.sh`
- `plugins/claude-ops/skills/observability/scripts/session-compare.test.sh`

Modified: the files named in the phases, `plugins/implementation/README.md`, `plugins/planning/skills/plan/templates/plan-md-anatomy.md`, and the manifests and CHANGELOGs for playbooks, planning, claude-config, discovery, claude-ops, implementation, work-items and knowledge.

Deleted: none.

### Alternatives considered

| Alternative | Rejected because | Switch condition |
|---|---|---|
| Repin `implementer` to `sonnet` (Q20 option A) | Every unplanned dispatch moves to Sonnet, and to Sonnet 4.5 on Bedrock, Vertex and Foundry (model-config#model-aliases) | The repo drops non-API providers, and every dispatch path carries a plan row |
| A shared `reference/implementer-contract.md` | The scope-fence and STOP rules would depend on a Read the worker may skip; `explorer.md:28-36` keeps its working rules inline | A harness feature injects a file into an agent's system prompt |
| Promote `effort` to a column in `cc-otel.sql` | It changes the cold Parquet schema, and `cc_metrics_cold()` (`cc-otel.sql:243-244`) has no `union_by_name` | The cold reader moves to `union_by_name` |
| File the fixture drift as a separate bug | The user chose to fix it here (Q45 alternative b) | None; the user decided |
| Work item per adopted row (precedent) | The user chose to implement here (Q43) | None; the user decided |

### Risks and mitigations

- **Gate S1 stalls.** The Prompting session said it will message this session when its merge commit lands. Decision point: when Phases 1-5 are green, check the gate. If it is still closed, ask the user (a user-approval gate) whether to wait, or to file Phase 6, Phase 5 step 9 and Phase 7 step 1 as one sub-issue of the parent and amend those acceptance criteria to "tracked in #<n>".
- **The inline contract copy drifts.** Mitigation: `agent-contract-sync.test.sh`, which the CI test discovery (`**/*.test.sh`) runs.
- **The dispatch-time provider check misses a provider.** Mitigation: the check lists the env vars model-config names. When in doubt it routes to `implementer`, which is the stronger model.
- **Docs anchors are derived slugs.** Mitigation: Phase 1 step 4 resolves each one.

## Blast radius

Blast radius: HIGH. The change touches more than 10 files across eight plugins plus `docs/` and `prompts/`. It adds an agent-instruction rule, changes how every future plan dispatches (Q20) and touches an observability surface. Two files it edits are being reworked by another live session (Gate S1). `git revert` undoes it before merge. CI gates cover the dispatch and agent surfaces: validate-plugin-contracts, changelog parity, the contract tests and test discovery.
Stress-test needed: Yes. Triggers: a new agent-instruction rule, a cross-cutting change, and a behavior change that other code depends on.

## Stress-test summary

`/planning:devils-advocate` ran in fresh context on the first draft: 4 HIGH, 4 MEDIUM, 4 LOW findings (`.work/opus-5-5-task-cost/devils-advocate.md`). A re-check against main followed. Outcomes:

- **#1 (stale base, HIGH):** fixed. The branch was fast-forwarded to `63cc66ad2` and every line was re-derived. Q8 is mostly done on main (#5387), so the Phase 2 Q8 work shrank. The agent's claim that Gate S1 had cleared was wrong: #5746 came from another machine's worker, and the owner session confirmed that its own reworking merge is still pending.
- **#2 (Phase 6 reverses a verdict merged on main, HIGH):** this displaces the user's Q42 answer, so it is put to the user at approval (Displaced answers).
- **#3 (caller's `model: opus` overrides the Sonnet frontmatter, HIGH):** fixed. Dispatch passes `model: sonnet` explicitly, and the eval asserts it.
- **#4 (cumulative temporality misattributed to #98193, HIGH):** fixed. A non-delta store exits 2, with a test.
- **#5 (provider not knowable at plan time):** fixed with a dispatch-time env check.
- **#6 (shared reference file weakens the contract):** fixed. The contract is inline, and a sync test guards it.
- **#7 (the plan's own per-invocation exception):** fixed. Phase 5 runs before Phases 2 and 3, and those dispatch through the real route.
- **#8 (500-line cap):** fixed. In-place rewording, with a `wc -l` check.
- **#9 (availableModels):** recorded in the agent's Claim record.
- **#10 (work skill fix-worker wording):** fixed.
- **#11 (sub-issue POST):** fixed in Phase 1.
- **#12 (`assert_absent`):** fixed in Phase 3.
- The re-check against main found two more: the changelog-parity script takes one mode per call, and the AGENTS.md generator drifts on main. Both are fixed.

The plan reviewer (fresh context, 9 IMPORTANT, 6 SUGGESTION) ran on the first draft, and all findings were applied before the stress-test.

## Execution shape

| Wave | Phases | Notes |
|---|---|---|
| A | 1 | Main session; issues and record draft |
| B | 4 and 5 in parallel | File-disjoint, except the planning CHANGELOG, which the orchestrator serializes |
| C | 2 and 3 in parallel | Dispatched through `scoped-implementer`, the first real use of the route |
| Gate S1 | | Wait for the Prompting merge, then `git merge origin/main` |
| D | 5 step 9, 6, 7 step 1 | |
| E | 7 steps 2-4 | |

| Phase | Surface | Model | Basis |
|---|---|---|---|
| 1 Tracker, record | main session | opus | Judgment over 48 ledger rows; remote writes |
| 5 Q20 routing | sub-agent worker (`implementer`) | opus | Cross-plugin contract change |
| 4 Observability compare | sub-agent worker (`implementer`) | opus | New SQL and reconciliation logic |
| 2 Pointer edits, rule | sub-agent worker (`scoped-implementer`) | sonnet | Closed file list, grep checks |
| 3 Row 7 | sub-agent worker (`scoped-implementer`) | sonnet | Closed file list, `contract.test.sh` oracle |
| 6 Thinking-off, Q42 | sub-agent worker (`implementer`) | opus | Per-row judgment |
| 7 Queue, links, PR | main session | opus | Remote writes, PR body |

Each worker is fenced to its phase's files. The orchestrator makes the CHANGELOG and manifest edits for any plugin two phases touch. The phase-verifier runs after each worker returns.

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) | Source |
|---|---|---|---|
| [EXEC-SHAPE] Q40: the compare context line links monitoring-usage first and the post's "Measure it yourself" section as a correlate, with no task count | Phase 4 context line and its test | Q38 rule 2; `source.md:327` heading | ledger Q38, Q40 |
| [EXEC-SHAPE] Q44: all three fixes (each adopted row names the docs section it trusts; one pointer line holding both links; Q13's stamp for post citations only) | Phase 1 row schema, Phase 2 first row | `questions.json` Q44; each fix makes two answered rows agree | ledger Q44 |
| [EXEC-SHAPE] Q47: each uncovered item is recorded with a disposition, and nothing is built | Phase 1 record | Brief out-of-scope; Q43 | ledger Q47 |
| [EXEC-SHAPE] Q48: the spec's Follow-ups name `/doctor prompt-audit`, ADR-0028 is unchanged, and `records.json` is unchanged because the doctor↔audit-instructions record already exists at `:1130-1165` | Phase 2 | `regrounding-main.md` | ledger Q48 |
| [EXEC-SHAPE] Q8 shrinks to the remaining files, because #5387 already added the doctor Boundary section | Phase 2 rows 3-6 | `audit-instructions/SKILL.md:115-129` on `63cc66ad2` | re-check |
| [EXEC-SHAPE] Q24 needs no new check | AC met by the existing CI gate | `validate-plugin-contracts.mjs:1074-1115`; `ci.yml` | grounding |
| [EXEC-SHAPE] Observability reads `effort` and temporality raw; `cc-otel.sql` is unchanged | Phase 4 | `prune-compact.sh:130`; `cc-otel.sql:243-244` | grounding, stress-test #4 |
| [EXEC-SHAPE] The worker contract is inline in both agents, with a sync test | Phase 5 steps 3-5 | `explorer.md:28-36` keeps working rules inline | stress-test #6 |
| [EXEC-SHAPE] Dispatch passes `model: sonnet` explicitly and checks the provider env vars at dispatch time | Phase 5 step 6 | sub-agents#choose-a-model order; model-config#model-aliases | stress-test #3, #5 |
| [EXEC-SHAPE] The upward-only rule stays; downward routing happens only by agent choice | Phase 5 step 6 | `implement-dispatch/SKILL.md:92-106` guard | plan review #5 |
| [EXEC-SHAPE] Phase 5 runs before Phases 2 and 3, which use the new route | Execution shape | Avoids a per-invocation exception | stress-test #7 |
| [EXEC-SHAPE] `render-index.sh` excludes eval-fixture trees, and AGENTS.md is regenerated, not hand-edited | Phase 2 | `render-index.sh check` reports DRIFTED on main (681789d59); the user's Q45 answer | Q45 alternative b |
| [FALLBACK] If Gate S1 stalls, the user decides between waiting and filing a sub-issue | Risks, approval gates | The owner's merge is pending | plan review #8 |

### Displaced answers and new external effects

Each row needs its own reply.

| # | Q | What the user said | What the plan now proposes | New external effect | Source |
|---|---|---|---|---|---|
| D1 | Q42 | "No exception": replace every audit-instructions row that overlaps `/doctor prompt-audit` with a pointer | Keep the 12 rows. On 2026-09-29, main recorded the two as complementary (#5387, `reference/native-doctor.md`). `doctor` cannot be invoked by the model (`model_invocable: false`), so a pointer row turns a finding the model reports into one only a human can produce. That breaks report-only and unattended runs and the audit-pass relay. The overlap evidence for 10 of the 12 rests on the vendor guide, which is MEDIUM. The record lists the overlap. | Fewer findings from `/claude-config:audit-instructions` if the original answer stands | stress-test #2 |
| D2 | Q24 | "An audit check flags any shipped agent with no `model:`" | No new check: the existing CI gate already does it | none | research update |
| D3 | Q8 | Name `/doctor prompt-audit` in the audit-instructions Boundary | Already on main (#5387); only the Routing wording changes | none | re-check |
| D4 | Q20/Q41 | Sonnet implements; ship here | A second agent, `scoped-implementer` (sonnet, medium), chosen by the effort-pin owner; dispatch also checks the provider at runtime | none beyond the PR | owner ruling, stress-test #5 |
| D5 | Q45 | One draft PR, a parent issue, sub-issues | Fix the `render-index.sh` fixture drift in this PR (user chose alternative b on 2026-10-01) | two new issues (parent, Q35 sub-issue); one draft PR | re-check; reconfirmed on the page |

## Open questions

None blocking beyond D1-D5 and Gate S1 timing.

## Handoff to implementation

Approval: approved by the user on the interview page (Q49, accepted 2026-10-01T22:49:31Z), with Q8, Q24, Q41 and Q42 reconfirmed as proposed and Q45 answered with alternative b (fix the generator here). The restated Brief was confirmed on the page at 2026-10-01T22:44:19Z.

### User-approval gates

- The Gate S1 stall decision (Risks).
- Any phase-verifier FAIL that needs a scope change.
- The PR stays a draft; flipping it to ready is the user's call (`/source-control:pull-request ready`).

### Execution shape ([EXEC-SHAPE] tagged)

See Execution shape above.

### Mechanical work

One commit per phase, with the phase tag updated in the same commit. `docs/topics/opus-5-5-task-cost/` is committed with Phase 1. `.work/` is never committed. Merge `origin/main` again after Gate S1 clears.
