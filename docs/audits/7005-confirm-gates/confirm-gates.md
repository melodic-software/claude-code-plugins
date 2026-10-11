# Confirm gates against the reversible and destructive split (slice 93)

Read-only audit for issue #7005. It edits no plugin, convention, script or settings file; this
folder holds its outputs, kept on a branch for the record.

- Pinned commit: `a2efc66ce3d29ed91de7c22cf2152995ce205eb8` (`confirm-gates-sha.txt`).
- Inventory: `bash confirm-gates.sh "$(cat confirm-gates-sha.txt)"`. It reads the pinned tree through
  `git grep` and `git show`, never the working tree.
- Count, taken before any classification and posted on the issue first: **175** rows
  (`confirm-gates-count.txt`). Per source: skill 164, agent 2, convention 6, hook 3, settings 0.
- `settings` is 0: `.claude/settings.json` at the pinned commit has `allow` and `deny` lists and no
  `permissions.ask` entry.
- `hook` rows are non-test code lines under `plugins/*/hooks/` that emit a PreToolUse
  `permissionDecision` of `ask` or `deny`. The guardrails blocking guards exit 2 and emit no
  permission decision, so they fall outside this definition and have no rows.

## Standard

The vendor statement is the Proactive output style: Claude "makes reasonable assumptions about
routine decisions rather than stopping to ask", and its instructions "tell Claude to check with you
in the conversation before an action that deletes data or changes a shared or production system"
([output-styles, Proactive](https://code.claude.com/docs/en/output-styles#proactive), read
2026-10-11; recheck when that section changes). This repository's `AGENTS.md` "When to stop" adds
the checkout boundary: another worktree or repo, a fleet host, user-scope config.

### Classes

Each row is classed by the action its gate guards. A row that holds no gate takes the class of the
action it discusses, or `reversible-local` when it discusses none.

- `reversible-local`: local and undoable: reads, local analysis, working-tree edits git can undo,
  local commits and reports, read-only fan-outs. Spend alone does not change the class; spend gates
  are named in the gate cell.
- `destructive`: deletes or loses data unrecoverably: untracked or outside-git deletes,
  `git reset --hard`, removing worktrees or branches with unpushed work, overwriting existing
  authored content, irreversible machine steps.
- `visible-outward`: other people see it: issues, PR comments, pushes, merges, tracker mutations.
- `cross-boundary`: leaves this checkout and session without being directly people-visible:
  user-scope or machine config, installing tools or dependencies, another repo, worktree or
  session's work, sending project content to a third-party service, launching a background agent.

### Proposals

- `keep-confirm`: keep the gate. On a row that holds no gate (its gate cell starts `not a gate:`)
  it means no change.
- `may-proceed`: the gate guards a routine reversible-local decision that has a recommended
  default; the agent could take it and report.
- `probe-first`: a read-only probe answers the question the gate asks the user.

### Verifier

A fresh-context verifier (three headless Claude Code sessions limited to Read, Grep and Glob, given
the row number, source, location, class and proposal but not the gate summaries) re-read every
`destructive`, `visible-outward` and `cross-boundary` row, every `may-proceed` and `probe-first` row,
and every fourth remaining `reversible-local` row. Its column holds `agree`, `disagree`, or
`not-sampled` for a row it did not check. The summary line below the table counts sampled rows only.

## Table

| # | source | file:line | gate | class | proposal | verifier |
|---|---|---|---|---|---|---|
| 1 | convention | `docs/conventions/config-cascade/README.md:534` | multi-agent setup apply writes config at any layer, user-global included, after a preview and an explicit yes (match: `explicit yes`) | cross-boundary | keep-confirm | agree |
| 2 | convention | `docs/conventions/invocation-context/README.md:58` | not a gate: criterion for forking a skill (body has no mid-flow confirmation) (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 3 | convention | `docs/conventions/skill-argument-shape/README.md:75` | not a gate: cites upstream guidance that destructive flags take explicit confirmation (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 4 | convention | `docs/conventions/skill-argument-shape/README.md:133` | not a gate: upstream-pointer row for the destructive-flag guidance (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 5 | convention | `docs/conventions/standards/README.md:73` | standards setup: explicit confirmation before converting a hand-authored standards README (overwrite of authored content) (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 6 | convention | `docs/conventions/standards/README.md:237` | standards setup: explicit confirmation before converting a hand-authored README into an index; never overwrite (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 7 | skill | `plugins/attribution/skills/audit/evals/fixtures/golden/c08-adversarial-rotation-sparse/case.md:3` | not a gate: eval fixture prose ("task before" matches "ask before") (match: `ask before`) | reversible-local | keep-confirm | not-sampled |
| 8 | skill | `plugins/attribution/skills/audit/evals/fixtures/golden/c08-adversarial-rotation-sparse/source.md:11` | not a gate: eval fixture prose ("task before") (match: `ask before`) | reversible-local | keep-confirm | not-sampled |
| 9 | skill | `plugins/attribution/skills/audit/evals/fixtures/golden/c09-adversarial-rotation-medium/case.md:3` | not a gate: eval fixture prose ("task before") (match: `ask before`) | reversible-local | keep-confirm | not-sampled |
| 10 | skill | `plugins/attribution/skills/audit/evals/fixtures/golden/c09-adversarial-rotation-medium/source.md:11` | not a gate: eval fixture prose ("task before") (match: `ask before`) | reversible-local | keep-confirm | agree |
| 11 | skill | `plugins/attribution/skills/audit/evals/fixtures/golden/c10-adversarial-rotation-dense/source.md:11` | not a gate: eval fixture prose ("task before") (match: `ask before`) | reversible-local | keep-confirm | not-sampled |
| 12 | skill | `plugins/biome-format/skills/setup/SKILL.md:88` | biome-format setup: install a dev dependency in the consumer repo only on an explicit go-ahead (match: `explicit go-ahead`) | cross-boundary | keep-confirm | agree |
| 13 | skill | `plugins/bugs/skills/write/SKILL.md:76` | bugs:write Q&A asks only for fields context cannot back (already probes first) (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 14 | skill | `plugins/code-tidying/skills/audit-dead-code/SKILL.md:127` | audit-dead-code: install or fetch a detector only after an explicit yes (match: `explicit yes`) | cross-boundary | keep-confirm | agree |
| 15 | skill | `plugins/code-tidying/skills/audit-dead-code/SKILL.md:156` | audit-dead-code: install or invoke a researched detector only after an explicit yes (match: `explicit yes`) | cross-boundary | keep-confirm | agree |
| 16 | skill | `plugins/code-tidying/skills/dissolve-comments/SKILL.md:184` | dissolve-comments: confirm widening scope to the repository rung; the non-interactive path already proceeds in safe mode and reports it (match: `AskUserQuestion`) | reversible-local | may-proceed | agree |
| 17 | skill | `plugins/code-tidying/skills/setup/SKILL.md:97` | code-tidying setup: never overwrite an existing consumer lane without explicit confirmation (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 18 | skill | `plugins/codebase-health/skills/audit/SKILL.md:197` | codebase-health audit: confirm before a fan-out over more than ~20 files (spend gate on read-only work) (match: `confirm with the user before`) | reversible-local | keep-confirm | not-sampled |
| 19 | skill | `plugins/context-budget/skills/audit/SKILL.md:204` | not a gate: lists interactive-only tools a headless sweep cannot price (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 20 | skill | `plugins/context-budget/skills/audit/reference/report.md:37` | not a gate: same interactive-only tool list in the report reference (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 21 | skill | `plugins/context7/skills/lookup/context/lookup.md:42` | context7 lookup: ask before guessing on an ambiguous library match; a read-only query of the top candidates answers it (match: `ask the user before`) | reversible-local | probe-first | disagree |
| 22 | skill | `plugins/coupling/skills/reduce/reference/change-mode.md:143` | coupling change apply: wait for confirmation of the classified site list (includes sites the human chose) (match: `explicit confirmation`) | reversible-local | keep-confirm | not-sampled |
| 23 | skill | `plugins/developer-experience/skills/audit-tools/SKILL.md:2` | developer-experience audit-tools: report-only, changes only after an explicit yes (scope: audit vs fix) (match: `explicit yes`) | reversible-local | keep-confirm | not-sampled |
| 24 | skill | `plugins/developer-experience/skills/setup/SKILL.md:15` | developer-experience setup: writes user-level conventions file and personal pointers only after a yes (match: `explicit confirmation`) | cross-boundary | keep-confirm | agree |
| 25 | skill | `plugins/discipline/skills/point-dont-copy/SKILL.md:114` | point-dont-copy: wait for the user to confirm the semantics map before port work (match: `wait for the user`) | reversible-local | keep-confirm | agree |
| 26 | agent | `plugins/discovery/agents/intent-tracer.md:376` | not a gate: subagent cannot call AskUserQuestion; questions return as text (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 27 | agent | `plugins/discovery/agents/researcher.md:399` | not a gate: subagent cannot call AskUserQuestion; questions return as text (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 28 | skill | `plugins/discovery/skills/explore/SKILL.md:173` | explore: ask before archaeology on intentionally deleted files; git status and log answer whether the delete was intentional (match: `ask before`) | reversible-local | probe-first | disagree |
| 29 | skill | `plugins/discovery/skills/explore/reference/workflow.md:109` | not a gate: open questions surface to the user or return in the payload (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 30 | skill | `plugins/discovery/skills/research/context/dispatch.md:55` | not a gate: parent re-surfaces a subagent's open questions (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 31 | skill | `plugins/discovery/skills/trace-intent/context/dispatch.md:140` | not a gate: parent re-surfaces a subagent's open questions (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 32 | skill | `plugins/disk-hygiene/skills/clean/SKILL.md:34` | disk-hygiene clean: mutate only after a fresh preview and explicit approval of one tier (match: `explicit approval`) | destructive | keep-confirm | agree |
| 33 | skill | `plugins/disk-hygiene/skills/clean/SKILL.md:137` | disk-hygiene clean: question surface for its destructive gate (prefer AskUserQuestion) (match: `AskUserQuestion`) | destructive | keep-confirm | agree |
| 34 | skill | `plugins/disk-hygiene/skills/setup/SKILL.md:160` | disk-hygiene setup: macOS manual Trash handoff only after explicit approval (match: `explicit approval`) | destructive | keep-confirm | agree |
| 35 | skill | `plugins/docs-hygiene/skills/audit-derivability/SKILL.md:97` | audit-derivability: offer a repo-wide sweep on an empty target, never start it unprompted (scope and spend) (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 36 | skill | `plugins/docs-hygiene/skills/compress/SKILL.md:114` | compress: offer a repo-wide run when no target is given (scope) (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 37 | skill | `plugins/docs-hygiene/skills/compress/SKILL.md:116` | compress: interview for scope and concurrency after the repo-wide run was accepted; prescribed defaults exist (match: `AskUserQuestion`) | reversible-local | may-proceed | agree |
| 38 | skill | `plugins/docs-hygiene/skills/compress/context/fan-out-orchestration.md:71` | compress: re-confirm before the next wave after 5 consecutive auto-reverts (spend circuit breaker) (match: `confirm with the user before`) | reversible-local | keep-confirm | agree |
| 39 | skill | `plugins/docs-hygiene/skills/rename-references/SKILL.md:91` | rename-references: several rename candidates detected, user picks the pair (intent only the user holds) (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 40 | skill | `plugins/docs-hygiene/skills/rename-references/SKILL.md:118` | rename-references: confirm step presents the buckets before any edit (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 41 | skill | `plugins/docs-hygiene/skills/rename-references/context/apply.md:48` | rename-references apply: gate proceed or abort after bucket counts (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 42 | skill | `plugins/docs-hygiene/skills/rename-references/context/apply.md:55` | rename-references apply: certain bucket asks "auto-apply N?" though its default is auto-apply (near-zero false positives) (match: `AskUserQuestion`) | reversible-local | may-proceed | agree |
| 43 | skill | `plugins/docs-hygiene/skills/rename-references/context/apply.md:61` | rename-references apply: chain-context bucket asks before applying (match: `AskUserQuestion`) | reversible-local | keep-confirm | disagree |
| 44 | skill | `plugins/docs-hygiene/skills/rename-references/context/apply.md:67` | rename-references apply: ambiguous bucket asks per match (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 45 | skill | `plugins/docs-hygiene/skills/rename-references/context/audit.md:33` | rename-references audit: single-token argument, ask what the new name is (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 46 | skill | `plugins/docs-hygiene/skills/rename-references/context/audit.md:34` | rename-references audit: several detected candidates, user picks (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 47 | skill | `plugins/docs-hygiene/skills/rename-references/context/audit.md:208` | rename-references audit: undetermined new name, suggest the user pick a target (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 48 | skill | `plugins/docs-hygiene/skills/rename-references/context/patterns.md:639` | rename-references: container or identifier, asked only after every probe came up empty (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 49 | skill | `plugins/docs-hygiene/skills/rename-references/context/triage.md:31` | rename-references triage: certain bucket asks auto-apply or review though the default is auto-apply (match: `AskUserQuestion`) | reversible-local | may-proceed | agree |
| 50 | skill | `plugins/docs-hygiene/skills/rename-references/context/triage.md:66` | rename-references triage: chain-context bucket asks before applying (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 51 | skill | `plugins/docs-hygiene/skills/rename-references/context/triage.md:131` | rename-references triage: ambiguous bucket asks per match (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 52 | skill | `plugins/docs-hygiene/skills/rename-references/context/triage.md:169` | rename-references triage: gate proceed or abort (match: `AskUserQuestion`) | reversible-local | keep-confirm | disagree |
| 53 | skill | `plugins/education/skills/quiz-me/SKILL.md:67` | quiz-me: a model-initiated offer waits for the user to accept (unrequested work) (match: `wait for the user`) | reversible-local | keep-confirm | not-sampled |
| 54 | skill | `plugins/evals/skills/design/SKILL.md:236` | evals design: never overwrite an existing criteria doc or suite without the diff and explicit confirmation (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 55 | skill | `plugins/evals/skills/plugin-eval/SKILL.md:82` | not a gate: AskUserQuestion listed among read-only eval tools (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 56 | skill | `plugins/evals/skills/plugin-eval/reference/case-authoring.md:122` | not a gate: AskUserQuestion listed among read-only eval tools (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 57 | skill | `plugins/event-storming/skills/methodology/SKILL.md:76` | event-storming methodology: ask the user's goal to pick the format (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 58 | skill | `plugins/event-storming/skills/simulation/SKILL.md:22` | event-storming simulation: user picks the next bounded context (interactive progression is the mode) (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 59 | skill | `plugins/event-storming/skills/simulation/SKILL.md:89` | event-storming simulation: user picks the next bounded context after the big picture (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 60 | skill | `plugins/firecrawl/skills/update/SKILL.md:27` | firecrawl update: every mutation (global npm install, SKILL.md rewrite) behind an explicit yes (match: `explicit yes`) | cross-boundary | keep-confirm | agree |
| 61 | skill | `plugins/firecrawl/skills/update/SKILL.md:61` | firecrawl update: nothing destructive without explicit approval; two approval gates (match: `explicit approval`) | cross-boundary | keep-confirm | agree |
| 62 | skill | `plugins/gaming/skills/dlss5/SKILL.md:195` | gaming dlss5 apply: explicit yes before writing into a game directory, one game per yes (match: `explicit yes`) | cross-boundary | keep-confirm | agree |
| 63 | skill | `plugins/gaming/skills/dlss5/SKILL.md:242` | gaming dlss5 remove: explicit yes before removing installed files from a game directory (match: `explicit yes`) | destructive | keep-confirm | agree |
| 64 | skill | `plugins/gaming/skills/dlss5/SKILL.md:282` | gaming dlss5 refresh after a game update: explicit yes before reinstalling (match: `explicit yes`) | cross-boundary | keep-confirm | agree |
| 65 | skill | `plugins/gaming/skills/dlss5/SKILL.md:326` | gaming dlss5 reset: explicit yes before rewriting the game's ini (match: `explicit yes`) | destructive | keep-confirm | agree |
| 66 | skill | `plugins/gaming/skills/dlss5/SKILL.md:415` | gaming dlss5 safety rules: apply, remove, refresh and reset each need explicit confirmation (match: `explicit confirmation`) | cross-boundary | keep-confirm | agree |
| 67 | skill | `plugins/github/skills/setup/SKILL.md:67` | github setup: wait before writing an unignored local overlay (machine-local values could reach a public commit) (match: `wait for the user`) | reversible-local | keep-confirm | not-sampled |
| 68 | skill | `plugins/harness-config/skills/audit-instructions/reference/conflict-criteria.md:469` | not a gate: audit criterion text citing disallowed-tools for AskUserQuestion (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 69 | skill | `plugins/harness-config/skills/audit-instructions/reference/conflict-criteria.md:601` | not a gate: worked conflict example quoting a CLAUDE.md line about AskUserQuestion (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 70 | skill | `plugins/harness-config/skills/audit-instructions/reference/conflict-criteria.md:604` | not a gate: worked conflict example quoting a skill's former gate (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 71 | skill | `plugins/harness-config/skills/audit-instructions/reference/conflict-criteria.md:608` | not a gate: measurement command counting AskUserQuestion mentions (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 72 | skill | `plugins/harness-config/skills/audit-instructions/reference/conflict-criteria.md:610` | not a gate: measurement command counting AskUserQuestion mentions (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 73 | skill | `plugins/harness-config/skills/audit-instructions/reference/conflict-criteria.md:628` | not a gate: describes the invariant-plus-surface wording (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 74 | skill | `plugins/harness-config/skills/audit-prompting-postures/reference/postures.md:262` | not a gate: posture-audit predicate that detects a wait for the user's choice (match: `wait for the user`) | reversible-local | keep-confirm | not-sampled |
| 75 | skill | `plugins/harness-config/skills/audit/SKILL.md:377` | harness-config audit --fix: a settings edit in auto mode needs the user's explicit approval (match: `explicit approval`) | cross-boundary | keep-confirm | agree |
| 76 | skill | `plugins/harness-config/skills/audit/context/procedures.md:64` | harness-config audit procedures: settings edit consent through the self-modification handshake (match: `explicit approval`) | cross-boundary | keep-confirm | agree |
| 77 | skill | `plugins/harness-memory/skills/stateless/SKILL.md:57` | harness-memory purge: delete auto-memory files only after explicit confirmation (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 78 | skill | `plugins/harness-memory/skills/stateless/context/purge.md:78` | harness-memory purge: confirmation gate quoting the manifest, with a backup offer (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 79 | skill | `plugins/harness-ops/skills/changelog/SKILL.md:136` | harness-ops changelog apply: scope gate over decision rows that become PRs per owner plugin (match: `AskUserQuestion`) | visible-outward | keep-confirm | agree |
| 80 | skill | `plugins/harness-ops/skills/known-issues/SKILL.md:176` | harness-ops known-issues create: draft first, never file an issue without explicit confirmation (match: `explicit confirmation`) | visible-outward | keep-confirm | agree |
| 81 | skill | `plugins/harness-ops/skills/lanes/SKILL.md:277` | not a gate: recheck trigger naming a lane prompt that would ask (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 82 | skill | `plugins/harness-ops/skills/plugins/context/converge.md:13` | harness-ops plugins converge: abort when no human can confirm (changes plugin install state) (match: `AskUserQuestion`) | cross-boundary | keep-confirm | agree |
| 83 | skill | `plugins/harness-ops/skills/plugins/context/converge.md:123` | harness-ops plugins converge: confirm per plugin, never a blanket yes (match: `AskUserQuestion`) | cross-boundary | keep-confirm | agree |
| 84 | skill | `plugins/harness-ops/skills/plugins/context/sync-install-enable.md:58` | harness-ops plugins sync: ask mode installs and enables plugins at user scope on the user's picks (match: `AskUserQuestion`) | cross-boundary | keep-confirm | agree |
| 85 | skill | `plugins/implementation/skills/implement/SKILL.md:144` | implement: a plan-tagged fallback is surfaced to the user (changes the approved plan) (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 86 | skill | `plugins/implementation/skills/implement/SKILL.md:145` | implement: an invented mid-implement action is surfaced to the user (scope expansion) (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 87 | skill | `plugins/implementation/skills/implement/SKILL.md:149` | implement: over-correction guard asks which pushed-back actions to drop (ambiguous intent) (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 88 | skill | `plugins/instruction-placement/skills/realign/SKILL.md:87` | instruction-placement realign: write a decline entry only on an explicit yes (the reason is the operator's) (match: `explicit yes`) | reversible-local | keep-confirm | not-sampled |
| 89 | skill | `plugins/machine-health/skills/setup/SKILL.md:127` | machine-health setup: enable a remediation (restart a service, clear temp files) only on an explicit yes (match: `explicit yes`) | destructive | keep-confirm | agree |
| 90 | skill | `plugins/markdown-format/skills/setup/SKILL.md:99` | markdown-format setup: install a dev dependency in the consumer repo only on an explicit go-ahead (match: `explicit go-ahead`) | cross-boundary | keep-confirm | agree |
| 91 | skill | `plugins/miro/skills/setup/SKILL.md:131` | miro setup: no Miro API request without explicit confirmation (third-party service) (match: `explicit confirmation`) | cross-boundary | keep-confirm | agree |
| 92 | skill | `plugins/multi-agent/skills/setup/SKILL.md:71` | multi-agent setup: show the diff, write config at any layer only on an explicit yes (match: `explicit yes`) | cross-boundary | keep-confirm | agree |
| 93 | skill | `plugins/mutation-testing/skills/audit/SKILL.md:44` | mutation-testing audit --full: state the estimated cost and confirm before running (spend gate) (match: `confirm before`) | reversible-local | keep-confirm | disagree |
| 94 | skill | `plugins/mutation-testing/skills/setup/SKILL.md:131` | mutation-testing setup: ask before installing a tool into the consumer project (match: `ask before`) | cross-boundary | keep-confirm | agree |
| 95 | skill | `plugins/overengineering/skills/justify/SKILL.md:193` | overengineering justify: ask before writing UNPROVEN when only the human can supply the evidence (match: `ask before`) | reversible-local | keep-confirm | not-sampled |
| 96 | skill | `plugins/overengineering/skills/realign/SKILL.md:274` | overengineering realign: write a suppression entry only on an explicit yes (the reason is the operator's) (match: `explicit yes`) | reversible-local | keep-confirm | not-sampled |
| 97 | skill | `plugins/planning/skills/design/SKILL.md:242` | planning design: frontier rounds are the skill's purpose; AskUserQuestion only on opt-in (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 98 | skill | `plugins/planning/skills/interview/SKILL.md:82` | not a gate: interview question-surface rule (AskUserQuestion is opt-in) (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 99 | skill | `plugins/planning/skills/interview/SKILL.md:115` | not a gate: interview surface rule (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 100 | skill | `plugins/planning/skills/interview/SKILL.md:149` | not a gate: Commits-you-to questions never go on an AskUserQuestion card (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 101 | skill | `plugins/planning/skills/interview/SKILL.md:175` | not a gate: where the recommendation marker sits on each surface (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 102 | skill | `plugins/planning/skills/interview/SKILL.md:351` | interview page surface: wait for the confirm-understanding event (the interview's confirmation gate) (match: `wait for the user`) | reversible-local | keep-confirm | agree |
| 103 | skill | `plugins/planning/skills/interview/SKILL.md:355` | not a gate: which questions may go on an AskUserQuestion card (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 104 | skill | `plugins/planning/skills/interview/SKILL.md:382` | interview confirmation gate: explicit confirmation of shared understanding before acting on the output (match: `explicit confirmation`) | reversible-local | keep-confirm | not-sampled |
| 105 | skill | `plugins/planning/skills/interview/context/gotchas.md:9` | not a gate: AskUserQuestion opt-in and cap (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 106 | skill | `plugins/planning/skills/interview/context/loop.md:258` | interview: hedged rows listed in the Step 3 restate for explicit confirmation (match: `explicit confirmation`) | reversible-local | keep-confirm | agree |
| 107 | skill | `plugins/planning/skills/interview/context/loop.md:288` | not a gate: rule is surface-agnostic (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 108 | skill | `plugins/planning/skills/interview/context/surface.md:248` | not a gate: page-surface degrade is never AskUserQuestion (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 109 | skill | `plugins/planning/skills/interview/templates/checklist.md:11` | not a gate: checklist line for the frontier-rounds loop (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 110 | skill | `plugins/planning/skills/plan/SKILL.md:120` | planning plan: alternatives presented side by side for the approval decision (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 111 | skill | `plugins/planning/skills/plan/SKILL.md:156` | planning plan: user may explicitly accept skipping design exploration (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 112 | skill | `plugins/planning/skills/plan/SKILL.md:158` | planning plan: ask clarifying scope questions on an ambiguous task, each with a recommendation (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 113 | skill | `plugins/planning/skills/plan/SKILL.md:159` | planning plan: open decisions surfaced before the plan body locks (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 114 | skill | `plugins/planning/skills/plan/SKILL.md:312` | planning plan: scoping confirm in plan mode (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 115 | skill | `plugins/planning/skills/plan/context/tag-decisions.md:17` | planning plan tag-decisions: interview round for below-bar decisions before the plan locks (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 116 | skill | `plugins/planning/skills/plan/templates/checklist.md:15` | planning plan checklist: wait for the user gate before any code edits (the user asked for a plan) (match: `wait for the user`) | reversible-local | keep-confirm | not-sampled |
| 117 | skill | `plugins/planning/skills/prd/SKILL.md:87` | planning prd: present the three tiers when the tier is unclear (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 118 | skill | `plugins/planning/skills/prd/SKILL.md:142` | planning prd: frontier rounds over open PRD questions (match: `AskUserQuestion`) | reversible-local | keep-confirm | agree |
| 119 | skill | `plugins/planning/skills/setup/SKILL.md:75` | not a gate: describes the use_ask_user_question toggle (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 120 | skill | `plugins/playbooks/skills/fable-5/context/communication.md:32` | not a gate: example label wording "confirm before relying on it" (match: `confirm before`) | reversible-local | keep-confirm | not-sampled |
| 121 | skill | `plugins/playbooks/skills/fable-5/context/reasoning-moves.md:5` | not a gate: heading ("task before" matches "ask before") (match: `ask before`) | reversible-local | keep-confirm | not-sampled |
| 122 | skill | `plugins/playbooks/skills/fable-5/context/trust-and-authority.md:61` | fable-5 trust: ask before any non-local action not named or granted; purely local work is outside the gate (match: `ask before`) | visible-outward | keep-confirm | agree |
| 123 | skill | `plugins/playbooks/skills/fable-5/context/trust-and-authority.md:75` | fable-5 trust: ask before trying an alternative when a denial's target is unclear (circumvention risk) (match: `ask the user before`) | cross-boundary | keep-confirm | agree |
| 124 | skill | `plugins/playbooks/skills/repo-sweep/catalogs/hygiene.md:256` | not a gate: catalog claim recording realign's explicit-yes write (match: `explicit yes`) | reversible-local | keep-confirm | agree |
| 125 | skill | `plugins/playgrounds/skills/use/SKILL.md:95` | not a gate: quoted example prompt mentioning the AskUserQuestion tool (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 126 | skill | `plugins/plugin-quality/skills/audit/SKILL.md:427` | plugin-quality audit: emit a work item to an external tracker only on explicit confirmation (match: `explicit confirmation`) | visible-outward | keep-confirm | agree |
| 127 | skill | `plugins/repo-fleet-hygiene/skills/audit/SKILL.md:291` | repo-fleet-hygiene audit: one explicit confirmation before any fleet mutation (branch and worktree deletion) (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 128 | skill | `plugins/repo-hygiene/skills/clean/SKILL.md:2` | repo-hygiene clean: destructive actions require explicit confirmation (description) (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 129 | skill | `plugins/repo-hygiene/skills/clean/SKILL.md:138` | repo-hygiene clean tree: explicit confirmation before git reset --hard; never auto-invoked (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 130 | skill | `plugins/repo-hygiene/skills/clean/SKILL.md:140` | repo-hygiene clean: never add the destructive-guard ack prefix without explicit confirmation (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 131 | skill | `plugins/repo-hygiene/skills/clean/SKILL.md:150` | repo-hygiene clean: question surface for its destructive gates (prefer AskUserQuestion) (match: `AskUserQuestion`) | destructive | keep-confirm | agree |
| 132 | skill | `plugins/repo-hygiene/skills/clean/SKILL.md:198` | repo-hygiene clean git: confirm before deleting never-pushed local branches (match: `confirm before`) | destructive | keep-confirm | agree |
| 133 | skill | `plugins/repo-hygiene/skills/clean/SKILL.md:226` | repo-hygiene clean tree-batch: one batch-wide gate; --include-dirty needs its own explicit confirmation (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 134 | skill | `plugins/repo-hygiene/skills/clean/context/clean-batch.md:14` | not a gate: notes the classifier blocks the pipeline even after explicit confirmation (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 135 | skill | `plugins/repo-hygiene/skills/clean/context/git-tree-reset.md:48` | repo-hygiene git-tree-reset: gate before --apply; --include-secrets and --allow-unpushed each confirmed (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 136 | skill | `plugins/ruff-format/skills/setup/SKILL.md:82` | ruff-format setup: install Ruff in the consumer repo only on an explicit go-ahead (match: `explicit go-ahead`) | cross-boundary | keep-confirm | agree |
| 137 | skill | `plugins/session-flow/skills/audit-friction/reference/classes.md:10` | not a gate: friction class C definition (proceed on reversible, authorized work) (match: `AskUserQuestion`) | reversible-local | keep-confirm | not-sampled |
| 138 | skill | `plugins/session-flow/skills/find-handoff/SKILL.md:133` | find-handoff: explicit yes or no before resuming a recovered handoff (wrong one is worse than none) (match: `explicit yes`) | reversible-local | keep-confirm | not-sampled |
| 139 | skill | `plugins/session-flow/skills/workflow/context/steps.md:34` | workflow steps: ask before investigating missing files; git status and log answer it (match: `ask before`) | reversible-local | probe-first | agree |
| 140 | skill | `plugins/songwriting/skills/object-writing/SKILL.md:83` | songwriting object-writing: ask before spawning when the subagent model tier is above the fleet default (spend) (match: `ask before`) | reversible-local | keep-confirm | agree |
| 141 | skill | `plugins/songwriting/skills/object-writing/SKILL.md:96` | songwriting object-writing: ask before spawning when the project names no fleet default (spend) (match: `ask before`) | reversible-local | keep-confirm | not-sampled |
| 142 | skill | `plugins/songwriting/skills/setup/SKILL.md:70` | songwriting setup: no overwrite of an existing file without explicit confirmation (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 143 | skill | `plugins/source-control/skills/babysit-loop/SKILL.md:99` | babysit-loop: interactive mini-interview over unresolved keys (stop mode, tier, merge rung) (match: `AskUserQuestion`) | visible-outward | keep-confirm | agree |
| 144 | skill | `plugins/source-control/skills/babysit-prs/reference/feedback.md:35` | not a gate: classifies a review-bot comment that states an explicit approval (match: `explicit approval`) | visible-outward | keep-confirm | agree |
| 145 | skill | `plugins/source-control/skills/babysit-prs/reference/feedback.md:90` | babysit-prs: after the advisory-round cap, report and wait for the user (match: `wait for the user`) | visible-outward | keep-confirm | agree |
| 146 | skill | `plugins/source-control/skills/babysit-prs/reference/safety.md:134` | babysit-prs safety: archived base repo, ask before any repository lifecycle decision (match: `ask the user before`) | visible-outward | keep-confirm | agree |
| 147 | skill | `plugins/source-control/skills/babysit-prs/reference/safety.md:801` | babysit-prs safety: a C4 or C5 PR waits for the user before merge (match: `waits for the user`) | visible-outward | keep-confirm | agree |
| 148 | skill | `plugins/source-control/skills/commit/SKILL.md:290` | not a gate: self-check (/usage confirms the model name before committing) (match: `confirm before`) | reversible-local | keep-confirm | not-sampled |
| 149 | skill | `plugins/source-control/skills/commit/reference/pathspec-commits.md:67` | commit pathspec: index dirty with another session's work, ask before committing or wait (match: `ask before`) | cross-boundary | keep-confirm | agree |
| 150 | skill | `plugins/source-control/skills/pull-request/reference/create.md:66` | pull-request create: remove main's copy of an ABSENT file only on explicit confirmation (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 151 | skill | `plugins/source-control/skills/pull-request/reference/merge.md:119` | pull-request merge: no GraphQL or a stack layer, wait for the user (match: `wait for the user`) | visible-outward | keep-confirm | agree |
| 152 | skill | `plugins/source-control/skills/pull-request/reference/merge.md:123` | pull-request merge script: not a melodic-software repository, wait for the user (match: `wait for the user`) | visible-outward | keep-confirm | agree |
| 153 | skill | `plugins/source-control/skills/pull-request/reference/merge.md:128` | pull-request merge script: ruleset does not require ci-status, wait for the user (match: `wait for the user`) | visible-outward | keep-confirm | agree |
| 154 | skill | `plugins/source-control/skills/pull-request/reference/monitor.md:26` | pull-request monitor: every merge outside the 4.2.1 rule waits for the user's approval (match: `waits for the user`) | visible-outward | keep-confirm | agree |
| 155 | skill | `plugins/source-control/skills/pull-request/reference/watch-handoff.md:81` | pull-request watch-handoff: launch a background monitor agent only on the person's explicit yes (match: `explicit yes`) | cross-boundary | keep-confirm | agree |
| 156 | skill | `plugins/source-control/skills/worktree/context/cleanup.md:34` | worktree cleanup: unlock a locked worktree only on explicit confirmation its owner is done (match: `explicit confirmation`) | cross-boundary | keep-confirm | agree |
| 157 | skill | `plugins/source-control/skills/worktree/context/cleanup.md:107` | worktree cleanup: remove main's copy only on explicit confirmation of a deliberate deletion (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 158 | skill | `plugins/source-control/skills/worktree/context/cleanup.md:259` | worktree cleanup: on confirmation the owner is done, re-check then remove the stale worktree (match: `explicit confirmation`) | destructive | keep-confirm | agree |
| 159 | skill | `plugins/testing/skills/cleanup/SKILL.md:86` | testing cleanup: renew an expired quarantine only on the user's yes (match: `only on the user's yes`) | reversible-local | keep-confirm | not-sampled |
| 160 | skill | `plugins/testing/skills/cleanup/SKILL.md:124` | testing cleanup: mutants dropped by the cap, continue only on the user's yes or a larger --max (match: `only on the user's yes`) | reversible-local | keep-confirm | agree |
| 161 | skill | `plugins/testing/skills/cleanup/SKILL.md:192` | testing cleanup: wait for batch approval before a local commit; deletes and merges were already gated per item (match: `wait for the user`) | reversible-local | may-proceed | agree |
| 162 | skill | `plugins/testing/skills/cleanup/evals/fixtures/cleanup/EXPECTED.md:34` | not a gate: eval fixture expectation (deletion applied only on the user's yes) (match: `only on the user's yes`) | reversible-local | keep-confirm | not-sampled |
| 163 | skill | `plugins/testing/skills/diagnose/context/fix-until-green.md:9` | testing diagnose: launch fix-until-green only on the user's yes; it edits the working tree and commits nothing (match: `only on the user's yes`) | reversible-local | may-proceed | disagree |
| 164 | skill | `plugins/testing/skills/diagnose/context/fix-until-green.md:62` | testing diagnose: revert a flagged test weakening only on the user's yes (deliberate or not is the user's call) (match: `only on the user's yes`) | reversible-local | keep-confirm | not-sampled |
| 165 | skill | `plugins/user-experience/skills/evaluate/SKILL.md:54` | user-experience evaluate: ask before sending project file contents to an MCP or plugin route (match: `ask before`) | cross-boundary | keep-confirm | agree |
| 166 | skill | `plugins/user-experience/skills/plan-user-research/SKILL.md:43` | user-experience plan-user-research: ask before sending project file contents to an MCP or plugin route (match: `ask before`) | cross-boundary | keep-confirm | agree |
| 167 | skill | `plugins/user-experience/skills/structure/SKILL.md:43` | user-experience structure: ask before sending project file contents to an MCP or plugin route (match: `ask before`) | cross-boundary | keep-confirm | agree |
| 168 | skill | `plugins/user-experience/skills/synthesize/SKILL.md:45` | user-experience synthesize: ask before sending project file contents to an MCP or plugin route (match: `ask before`) | cross-boundary | keep-confirm | agree |
| 169 | skill | `plugins/wizard/skills/generate/SKILL.md:104` | wizard generate: explicit approval of the stages before the human runs a credential-handling script (match: `explicit approval`) | cross-boundary | keep-confirm | agree |
| 170 | skill | `plugins/wizard/skills/unattended/SKILL.md:41` | wizard unattended: wait for the user to confirm the ordered stages, irreversible steps marked (match: `wait for the user`) | destructive | keep-confirm | agree |
| 171 | skill | `plugins/wizard/skills/unattended/SKILL.md:181` | wizard unattended: explicit approval of the stages before the agent runs -Test (match: `explicit approval`) | cross-boundary | keep-confirm | agree |
| 172 | skill | `plugins/work-items/skills/triage/SKILL.md:134` | work-items triage: wait for the user's explicit direction before mutating a tracker item (match: `wait for the user`) | visible-outward | keep-confirm | agree |
| 173 | hook | `plugins/context-budget/hooks/settings-write-ask.mjs:110` | context-budget hook: ask on any Write or Edit to a Claude Code settings file (match: `permissionDecision: 'ask'`) | cross-boundary | keep-confirm | agree |
| 174 | hook | `plugins/multi-agent/hooks/drift-checker-fetch-gate.mjs:58` | multi-agent hook: deny a drift-checker WebFetch outside first-party docs hosts (exfiltration guard) (match: `permissionDecision: 'deny'`) | cross-boundary | keep-confirm | agree |
| 175 | hook | `plugins/testing/hooks/test-weaken.sh:147` | testing hook: deny an added skip or removed test unless a test-change reason is added (opt-in rule) (match: `permissionDecision":"deny"`) | reversible-local | keep-confirm | not-sampled |

sampled: 106; disagree: 6

## Totals

| class | keep-confirm | may-proceed | probe-first | rows |
|---|---|---|---|---|
| reversible-local | 92 | 6 | 3 | 101 |
| destructive | 28 | 0 | 0 | 28 |
| visible-outward | 14 | 0 | 0 | 14 |
| cross-boundary | 32 | 0 | 0 | 32 |

44 of the 175 rows hold no gate: the fixed pattern also matches tool lists, quoted examples, eval
fixtures, and the substring "task before". They stay as rows because the plan forbids sampling.

Every `destructive`, `visible-outward` and `cross-boundary` gate already confirms, and this audit
proposes keeping each one. The relaxation candidates are all `reversible-local`:

- `may-proceed`: rows 16 (code-tidying dissolve-comments scope widening), 37 (docs-hygiene compress
  scope and concurrency interview), 42 and 49 (docs-hygiene rename-references certain bucket), 161
  (testing cleanup local batch commit), 163 (testing diagnose fix-until-green launch).
- `probe-first`: rows 21 (context7 lookup ambiguous match), 28 (discovery explore deleted files),
  139 (session-flow workflow missing files).

Spend gates (rows 18, 35, 38, 93, 140, 141) are classed `reversible-local` with `keep-confirm`: the
vendor statement says nothing about spend, so this audit keeps them and names them for the gate.

## Verifier disagreements

The verifier disagreed on 6 of 106 sampled rows. Each goes to the user gate with the table; the
table keeps the auditor's class and proposal, and the verifier's reading is below.

| row | auditor | verifier |
|---|---|---|
| row 21 | reversible-local, probe-first | reversible-local, may-proceed: take the best library match and report; a wrong lookup is cheap to redo |
| row 28 | reversible-local, probe-first | reversible-local, may-proceed: archaeology on deleted files is read-only, so proceed and report |
| row 43 | reversible-local, keep-confirm | reversible-local, may-proceed: chain-context rename matches are git-undoable doc edits with a stated default |
| row 52 | reversible-local, keep-confirm | reversible-local, may-proceed: the proceed gate before a git-undoable rename sweep the user invoked could go |
| row 93 | reversible-local, keep-confirm | reversible-local, may-proceed: the user passed `--full` explicitly and the run restores the code |
| row 163 | reversible-local, may-proceed | cross-boundary, keep-confirm: launching the multi-agent fix-until-green workflow needs the user's explicit opt-in |

Rows 21 and 28 differ only in which relaxation fits; either way the gate stops asking first. Rows
43, 52 and 93 are where the verifier would relax more than the auditor. Row 163 is where it would
relax less, and its reading is the more cautious one.

## Per-class toggle proposals

Proposals only; nothing here is applied. Each relaxation is a per-plugin toggle, never a global
switch, with the policy floor the plan names: the team block in the owning plugin's convention
doc (`docs/conventions/<plugin>.md` in the consumer repository) sets the posture, and a user's
`userConfig` value can only tighten it (ask more), never relax it.

| class | proposal | home |
|---|---|---|
| reversible-local, may-proceed rows | one boolean per owning plugin, default `ask` until approved, value `proceed` takes the stated default and reports it in one line | `code-tidying`, `docs-hygiene`, `testing` convention blocks plus a matching `userConfig` key |
| reversible-local, probe-first rows | no toggle: rewrite the gate to run the read-only probe and ask only when it does not settle the question | `context7`, `discovery`, `session-flow` skill bodies |
| destructive | no toggle; keep every confirm | none |
| visible-outward | no toggle; keep every confirm (merge authority already has its own rung ladder in `/source-control:babysit-loop`) | none |
| cross-boundary | no toggle; keep every confirm | none |

## Probe-not-question rule placement

The rule already exists twice: `/planning:interview` and its siblings run a self-answer step that
answers facts before asking (`plugins/planning/context/self-answer.md`), and `/playbooks:fable-5`
has the communication chapter section "Decide, or ask". Proposed placement: one line in fable-5's
"Decide, or ask" pointing at the planning self-answer step as the probe to run before any question,
so the three `probe-first` rows can cite one rule. An operator default reported under that rule is
stated in plain words ("Proceeding with X because Y; say so to change it"), with no shorthand reply
token.

## Proposed AGENTS.md wording (not applied)

The current "When to stop" section already draws the split: keep going when a step needs no input,
stop before anything destructive or outside this checkout. The only addition this audit supports is
the probe rule, appended to its first sentence:

> When a step doesn't need the user's input, keep going, with status notes in the same message as
> the next action; before asking a question, run any read-only probe that would answer it.

The repository's instruction-economy rule asks a new standing instruction to name observed-stumble
evidence. This audit is text evidence (three gates that ask what a probe answers), not observed
stumbles; `/session-flow:audit-friction` class C over real sessions is the source that would supply
it.

## WS-P Phase 15 entries

The plan asks for the WS-P Phase 15 entries any relaxation would add. WS-P is a local plan that is
not in the repository, so this record cannot name them; Kyle holds that plan.

## User gate

Pending. Kyle approves by class and names exceptions by row number; the decision is recorded here
as an `Approved classes:` line and an `Exceptions:` line, and each approved class or row is filed as
its own slice. Until then nothing changes.
