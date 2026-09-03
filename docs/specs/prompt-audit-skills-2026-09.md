# prompt-audit over every skill, 2026-09

Record of running the bundled `/claude-api prompt-audit` (Claude Code 2.1.258) over every skill in this marketplace against Claude Fable 5.1. Written so the unapplied remainder is resumable without re-auditing, so the catalog gaps it exposed are filed, and so the follow-ups ship in the same PR.

## Decay rule

Point-in-time, stamped 2026-09-02. The check is the quoted text, never the status and never the line number. If a finding's quoted source text is still present at or near the cited path, the finding is open. A quote that matches nothing has been applied, superseded, or moved.

## Contents

- [Stated assumptions](#stated-assumptions)
- [Corpus](#corpus)
- [Method](#method)
- [Results by wave](#results-by-wave)
- [Catalog gaps](#catalog-gaps)
- [Withheld findings](#withheld-findings)
- [Follow-ups](#follow-ups)

## Stated assumptions

Per prompt-audit Step 0, established from the request and the repository, not by asking.

- **Scope.** Every markdown file under `plugins/*/skills/` excluding `vendor/` and `evals/`, plus `plugins/*/agents/*.md`. Descriptions and trigger text are in scope under the guide's trigger-versus-behavior split.
- **Target model.** Claude Fable 5.1, named by the operator and the newest model the repository's own docs point at. Where the migration guide carries Opus 5 guidance with no Fable 5.1 counterpart, Opus 5 guidance applies; on conflict Fable 5.1 wins.
- **Labels.** Each finding is labeled `fleet` (reason documented model-agnostically or convergent across current model guides) or `fable-5-1` (reason specific to Claude Fable 5.1). Both are applied at high and medium confidence.
- **Repo conventions are not binding.** ADRs, CI gates, and `check-skill.sh` were updated or removed where they blocked a warranted change; a superseding ADR lists each accepted decision this audit contradicted.

## Corpus

Fresh `origin/main` at e69547e3e (2026-09-02).

| Measure | Count |
|---|---|
| Plugins | 74 |
| Skills (SKILL.md, excluding vendor and eval fixtures) | 241 |
| Skill-owned markdown files in scope | 798 |
| Lines in scope | ~115,000 |
| Agent definitions | 13 |

Greppable signals before the audit: 308 caps-emphasis words (`MUST|NEVER|ALWAYS|CRITICAL|IMPORTANT`), 245 numbered-step headers, 210 bare prohibition bullets, 162 migration-relative phrasings, 285 tracker references, 475 dated stamps, 103 Claude Code version pins, 7 retired-model mentions, 2 numeric output caps, 1 narration suppressor, 0 think-step-by-step scaffolds.

## Method

One fresh-context subagent per plugin (Claude Fable 5.1 through wave 3b; Claude Opus 5 with the same briefs once the Fable model limit began refusing subagent turns, the target model unchanged) reads the prompt-audit guide and the Fable 5.1 migration sections, audits every in-scope file of that plugin, and writes a report with one row per finding (`file:line`, quoted evidence, pattern row, why obsolete for the target, confidence, action, label, catalog row) and one proposed hunk per finding. The main session reviews each report, applies accepted hunks, updates the skill's evals when its body changed, runs `check-skill.sh` on each touched skill, bumps the plugin's patch version with a CHANGELOG line, and commits once per plugin.

Waves, ordered by usage, pipeline centrality, and signal density:

| Wave | Plugins |
|---|---|
| 1 | session-flow, planning, source-control, implementation, plus every `setup` skill as one cross-cutting lane |
| 2 | work-items, review, discovery, verification, toolchain, testing, bugs, debugging, discipline |
| 3a | claude-config, claude-ops, claude-memory, playbooks |
| 3b | skill-quality, plugin-quality, autonomy, instruction-placement, context-budget, context-guard, rate-limit-guard, guardrails, computer-use, overengineering, improvement |
| 4a | docs-hygiene, code-tidying, repo-hygiene, repo-fleet-hygiene, disk-hygiene, codebase-health, ai-slop, provenance |
| 4b | tdd, mutation-testing, event-storming, architecture, coupling, naming, domain-driven-design, mcp-tools, evals, performance, prototype, visualization, wizard, machine-health |
| 5 | knowledge, songwriting, education, adhd, ai-briefing, kindle-dedrm, context7, firecrawl, x, dometrain, miro, playwright, github, playgrounds, desktop-notification, eol-normalizer, actionlint, bash-format, biome-format, go-format, markdown-format, powershell-format, ruff-format, typos-format |

## Fleet decisions

Calls made once so that per-plugin auditors' identical findings are treated the same way everywhere.

- **Gather-block wording.** The "Repository context. Gather first" block that replaced git pre-compute lines in about 55 skills carries the sentence "Keep these as separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute block as one shell invocation, and a worktree-isolated session refuses a compound command that contains git." That is the fleet standard. The issue number and "do not fold them back" it replaced were archaeology; the remaining contrast is structural, not a version diff, and is not rewritten per plugin.
- **"The pipe is the bound" sentence.** Kept fleet-wide in its one-sentence form. It stops a read-time cap from replacing the pipe, which is a live constraint, not harness trivia.
- **Third-party "think before code" priming.** Every presence-gated invocation of `andrej-karpathy-skills:karpathy-guidelines` (debugging, implementation, planning) is removed, not kept: its first primed rule is the plan-before-acting scaffold prompt-audit Group 1b deletes, and the plugin exists in no installed marketplace. The surviving scope rules (simplest change, surgical edits) stay as one plain sentence.
- **Phantom `dotnet-*` and `cloudflare` references.** Every forward reference to `dotnet-diag:*`, `dotnet-msbuild:*`, `dotnet-test:*`, `dotnet-data:*`, and `cloudflare:web-perf` is removed (toolchain, implementation, testing, verification). No installed marketplace carries them and the toolchain plugin's own text called the family "planned".
- **Descriptions.** Near-synonym trigger lists become intent categories with a few exact phrases kept; `check-skill.sh` check 3 is advisory (follow-up F5) and the dropped phrases are recorded per plugin below.

## Cross-cutting commits

Landed on the branch before or alongside the waves, each its own commit:

| Commit | What |
|---|---|
| a4450c48c | Removed the `worktree.baseRef: head` override from `.claude/settings.json` and its rationale from the topic-docs convention (operator request during the audit). |
| 973da374a | Scaffold: this record, the topic Brief, the `skill-bodies-state-current-rules` rule, the regenerated rules index. |
| ce8e6b58a | Moved git pre-compute out of the composed substitution block in 50 skills across 22 plugins, so worktree-isolated sessions can load them; each plugin patch-bumped; one docs-hygiene test re-anchored to the new bullet shape. Prompted by the interview skill failing to load in this worktree. |
| a694011bf | `skill-quality` check 3 (trigger-phrase preservation versus the base ref) made advisory: a dropped phrase warns naming it instead of failing the run (follow-up F5); tests retargeted; 0.20.10. |

## Results by wave

One row per applied plugin. "Applied" and "Withheld" name finding ids from `.work/prompt-audit-skills/reports/<plugin>.md`; setup-lane items carry their `T<n>` and `setup-F<n>` ids. Withheld ids are listed in [Withheld findings](#withheld-findings). The check-3 phrases each plugin deliberately dropped are listed after the table, computed by `check-skill.sh` with `CHECK_SKILL_BASE_REF=origin/main`.

| Wave | Plugin | Commit | Version | Applied | Withheld |
|---|---|---|---|---|---|
| 1 | session-flow | 221e8bdec, renumbered in 498dd4812 | 0.34.22 | F1 to F25 (one `apply-modified`) | F26 to F36 |
| 1 | source-control | 01268af79 | 0.55.40 (renumber before the PR) | F1 to F71, setup-lane T2 | F72 to F81 |
| 2 | work-items | 7c5078774 | 0.39.52 (renumber before the PR) | F1 to F16, setup-lane T1 sites 6 to 11, T2, T4 site 4, setup-F2, setup-F3 | F17 to F23 |
| 3a | claude-memory | d8452ead8 | 0.11.15 | F1 to F11 (one `apply-modified`) | F12 |
| 1 | planning | 66314fd1c | 0.35.5 | F1 to F29 (F1 to F7 already landed in ce8e6b58a; F35 `apply-modified`), L1 | F30 to F34, F36 |
| 1 | implementation | 12b3180de | 0.16.2 | F1 to F14 (F1 already in place), L1 | F15 to F20 |
| 2 | toolchain | b0367f42f | 0.13.13 | F1 to F12 | F13 to F18 |
| 2 | review | 64cc882d8 | 0.26.17 | F1 to F15, setup-lane T2 | F16 to F21 |
| 2 | verification | d057a497b | 0.6.4 | F1 to F5, F7, F10 (as L1), L1, setup-lane F7 | F6 (superseded by L1), F8, F9 |

Notes on the wave-1 and wave-2 commits:

- source-control: `babysit-prs/scripts/tests/test_skill_contract.py` asserts the replacement prose for F2, F23, F35, F36, and F38 instead of the removed markers; no behavior assertion changed. F26 edited `guard_contract.py` claim strings and regenerated `reference/guard-contract.md`.
- session-flow: `keep-going/context/continuation.md` retargets one pointer to the renamed section.
- work-items: every gate green except `onboard-adapter/scripts/generate-adapter.test.sh` case 116, which fails on this host with unchanged files (follow-up F10).
- claude-memory: audit eval case 10 reworded to the new text.
- planning: `tests/interview-defenses.test.sh` refreshes four section digests the accepted edits changed (Stance, Step 4, the open-question register, the unattended path); every pinned defense line inside them still matches. Nine eval-case digest assertions in that suite fail on this host with `interview/evals/evals.json` unchanged (follow-up F10). `interview/SKILL.md:217` retargets one pointer to the handoff discipline after F19 emptied the flush section. L1 landed on the check flow's step 3 (the `vault_backend` wording), which is where planning carries it.

### check-3 dropped phrases

Each phrase below was a single-quoted trigger in the skill's description at `origin/main` and is absent after the rewrite. The description now names the intent category instead.

- **session-flow** keep-going (9): 'are you stuck', 'carry on', 'continue', 'keep going', 'pick up where you left off', 'poke it', 'resume', 'we got interrupted', 'you got cut off'.
- **source-control** babysit-loop (8): '--merge c3-this-run', 'autopilot', 'babysit loop', 'babysit the PR queue continuously', 'drain the PR queue', 'keep merges flowing', 'run the babysit loop', 'stand up the merge lane'. babysit-prs (7): 'advance all open PRs', 'babysit PRs', 'babysit my PRs', 'babysit worker', 'keep my PRs moving', 'run the PR queue on autopilot', 'watch my open PRs'. setup (8): 'check babysit config', 'configure babysit', 'configure commit convention', 'override the team convention locally', 'set my personal commit convention', 'set up source-control', 'source-control setup', 'what commit format does this repo use'.
- **work-items** track (22): 'add a ticket', 'add a work item', 'add an issue', 'audit stale claims', 'audit work items', 'check overdue recurring items', 'claim a work item', 'close a ticket', 'close a work item', 'close an issue', 'list issues', 'list tickets', 'list work items', 'recheck a recurring item', 'search work items', 'start a ticket', 'start a work item', 'start an issue', 'what work items are open', 'whats due', 'work items dashboard', 'work-item stats'. work (11): 'auto-select a work item', 'do the next thing', 'grab the next ticket', 'grab the next work item', 'pick work', 'start on the backlog', 'what should I work on next', 'work an item', 'work the next issue', 'work the next item', 'work the next ticket'. decompose (15): 'break a plan into tickets', 'create issues from plan', 'decompose into tickets', 'decompose this PRD', 'decompose', 'publish the brief to the tracker', 'publish the spec as a container', 're-decompose', 're-slice', 'reroute the plan', 'spec container', 'split this plan into work items', 'the spec changed, redo the tickets' (the original joined the halves with an em dash), 'turn the plan into tickets', 'vertical-slice this plan'. ship (11): 'close out the container', 'container status', 'drive the spec', 'macro status', 'resume the multi-session effort', 'ship the container', 'ship this spec', 'spec journey', 'whats next in the container', 'where are we on the spec', 'work the spec container'.
- **claude-memory**: none.
- **implementation**, **toolchain**, **verification**: none.
- **review** fanout (5): 'breadth review', 'fan out review', 'review from every angle', 'review this from all sides', 'run all reviewers'.
- **planning** draft-goal-condition (8): '/goal or /loop', 'my /goal is too long / over the limit', 'set up an autonomous goal', 'should this be a routine', 'should this be a workflow', 'turn this into a completion condition', 'what kind of loop is this', 'write a goal condition'. devils-advocate (5): 'argue against this', 'challenge this plan', 'find the holes in this', 'is the incumbent still the right choice', 'reconsider the current approach'.

## Catalog gaps

Findings whose pattern has no row in `plugins/claude-config/skills/audit-instructions/reference/criteria.md`.

(filled per wave)

## Withheld findings

Low-confidence and `flag` items, reported but not applied.

(filled per wave)

## Follow-ups

Inventoried here as they arise and shipped in the PR body verbatim.

- F1. Write one superseding ADR covering every accepted ADR decision this audit contradicted (at minimum ADR 0004 D-1 and D-3, ADR 0006's applied-set gate); decide with the operator whether ADR 0005 and ADR 0008 are also retired.
- F2. Audit the out-of-scope prompt surfaces the same way: hooks prompt text, output styles, `.claude/rules`, `CLAUDE.md`, `AGENTS.md`.
- F3. Behavior measurement beyond the wave-1 spot-check: route to `claude-config:unhobble`.
- F4. Graduate `docs/topics/prompt-audit-skills/PLAN.md` into this record and remove it before the PR (contract-slice prune gate).
- F5. `plugins/skill-quality/scripts/check-skill.sh` check 3 hard-fails any trigger phrase dropped versus the base ref. That blocks prompt-audit's documented fix for trigger-case enumeration (near-synonym lists become intent categories). Change check 3 to a warning, update its tests, and record the deliberately dropped phrases per skill in this record. Must land before the PR so the skill-quality CI gate passes.
- F6. Verify and stamp the undated harness-behavior claims the audit flagged as `I12` items (session-flow: `/recap` trigger and the Skill-invocable allowlist, the usage-limit reset surface, `cleanupPeriodDays` default, `/clear` transcript and scheduled-task behavior). Each becomes a four-part upstream-drift record or a doc pointer. Collected per plugin as the waves run. source-control adds: GitHub `mergeStateStatus` precedence and `baseRefOid` staleness (freshness.md), the permission-mode and wrapper-strip claims in safety.md, and the ScheduleWakeup clamp, `/loop` expiry, Monitor-on-resume, and sandboxed-GraphQL claims across babysit-prs, babysit-loop, pull-request, and worktree.
- F7. `pull-request` hardcodes one vendor's review bot (login, emoji signalling, timing) in `reference/monitor.md` gotchas and `reference/readiness.md` Gate 5, against the file's own "discover actors, don't hardcode them" rule. Parameterize Gate 5 on the discovered reviewer login and move the vendor shapes into a dated reference-shapes note with a recheck trigger.
- F8. `source-control` cites sibling-plugin files by relative path (`../../../../autonomy/...`, `../../../../../prompts/...`) in `babysit-loop/reference/promotion-evidence-resolution.md` and `babysit-prs/reference/safety.md`. Those resolve only in the marketplace checkout, never in an installed plugin. Convert to the raw-URL form the plugin already uses at `babysit-loop/SKILL.md:40`. review adds: `agents/ecosystem-specialist.md:22`, `fanout/context/fix-pass-mode.md:7`, `quality-gate/context/close-out.md` (four sites), and `quality-gate/context/spec.md` (three sites) cite marketplace `docs/` paths or sibling-plugin files by relative path. review also adds two undated claims to F6: the bundled `/code-review` and managed Code Review service tiers in `quality-gate/context/pr.md` and `code.md`, and the "built-in `/security-review` is unusable in CI" claim in `security-review/SKILL.md`.
- F9. `planning/skills/wayfind/SKILL.md` pre-compute silently coerces a non-string `container_label` to `work-map`, which `context/tracker-mechanics.md` says is a configuration error that must never proceed. Make the pre-compute fail loud or surface the raw value, matching the doc.
- F11. `work-items` carries the same 60-line lane-telemetry upsert as a fenced shell block in `work-loop/reference/telemetry-upsert.md` and `attend-queue/reference/telemetry-upsert.md`, transcribed by the model on every cycle, with a classifier-fallback section asking it to re-derive gate order by hand (prompt-audit Group 4, an LLM executor for a deterministic plan). Extract it into `plugins/work-items/scripts/lane-telemetry-upsert.sh` with a co-located test, taking lane, instance, repo, issue, and body-file arguments and exiting non-zero on each refusal branch; both references then invoke it. Deferred from the audit because it is a mechanism change, not a prose hunk. work-items also adds six undated harness and `gh` claims to F6 (classifier refusals of `permissions.allow` widening and of the `reclaim` call, the compound-shell block, sandboxed GraphQL 403).
- F12. `shell: bash` frontmatter selects the shell for `!`...`` injections. Skills whose pre-compute block became empty when the git lines moved into body calls still carry the key inert (debugging F5 found one). Sweep every SKILL.md: where no injection remains, drop the key; `check-skill.sh` check 19 stays green either way.
- F13. `playbooks:boris` presents Fable 5 as the current top model and its launch-era classifier behavior as current (`skills/boris/SKILL.md:58,133`); upstream has not published Fable 5.1 tips. Re-sync through `/playbooks:update` when it does, and until then qualify the Model row "as of the 2026-07-24 sync".
- F14. The `fable-5` playbook's own regeneration trigger ("a model-version change", `skills/update/SKILL.md:39`) has fired with Fable 5.1. The audit adds the guide-backed minimum, a `fable-5-1.md` adaptation chapter; regenerating the whole pack from Fable 5.1 is the maintainers' larger call. playbooks also adds to F8: `reference/model-adaptation/opus-5.md:207-208` cites a probe record (`thinking-off-probe-2026-07-26.md`) that exists nowhere in the repository. And to F6: the cache-pricing stamp at `skills/fable-5/context/orchestration.md:97` carries a date but no recheck trigger.
- F15. The statusline compose transform in `unwrap-before-compose.md` (synced between `context-guard` and `rate-limit-guard`) is a pure function of the effective `statusLine` string that the model hand-executes over roughly a hundred lines of prose, with eight eval cases checking the arithmetic (prompt-audit Group 4). Extract it into a synced `scripts/compose-statusline-wiring.sh` with the round-trip check inside, shrink the reference to the contract, and turn those eval cases into script tests. Deferred from the audit as a mechanism change. rate-limit-guard also adds to F6: the undated "Monitors is an experimental Claude Code component" claim in `reference/reader-contract.md:206-209`.
- F16. `claude-ops/skills/plugins/SKILL.md:268-276` records that its own probe's recheck trigger has fired (the CLI moved from 2.1.218 to 2.1.240 with the claim un-retested). Re-run the probe and refresh the stamp. claude-ops also adds nine undated harness and upstream-issue claims to F6 (bundled `doctor` gating, `audit-native-overlap` alias examples, `inventory` command aliases, the WebFetch truncation window, the `CLAUDE_PLUGIN_DATA` export claim, the `lanes` "verified on this machine" lines, the `observability` `session_id` and Stop-hook gotchas, upstream issue states in `read-routing.md` and `sync.md`, and the triggerless `surfaces.md` stamp) and two measured figures (`backups/` retention, the 97 percent and 50 MB figures in `observability`).
- F17. `context-guard/skills/setup/SKILL.md` runs four fixed read-only probes (jq presence, installed shim versus shipped source, session snapshot, `zones.json`) as model-issued Bash calls where a `## Pre-computed context` block would run them before the body loads (prompt-audit Group 4). Adding one is a mechanism change: the block must pass `scripts/check-skill-precompute-compose.sh` and stay inside the worktree guard's rule that a composed block expands nothing but bare `$HOME`, so it is deferred from the audit. context-guard also adds to F6: the undated `disableAllHooks` / `allowManagedHooksOnly` claims in `skills/setup/SKILL.md:93-96` and `reference/reader-contract.md:503-507`, the undated PowerShell routing note in `statusline-edit.md:106-109`, and the folklore-number paragraph at `reader-contract.md:383-391`, which is dated but has no recheck trigger.
- F18. `autonomy/reference/autonomous-pipeline-reminder.md` (out of audit scope; cited only by the README and a hook) rewords the vendor's autonomy block under the repo's no-copy rule and omits the Fable 5.1 clause "Do not stop because the context or session is long"; the guide calls the opening sentence load-bearing as written. Weigh the no-copy rule against that claim and add the missing clause in the plugin's own words. autonomy also adds to F6: the undated `AGENTS.md`-reachability claim stated three times (`skills/setup/SKILL.md:267`, `context/prerequisite-resolution-slice.md:38-39`, `reference/prerequisite-resolution.md:86-88`), the undated empirical telemetry claims in `reference/telemetry.md`, and the "shipped first-party mechanisms today" claims in `reference/runner/escalation.md:140-152`.
- F19. `plugin-quality/skills/audit/SKILL.md:58-92` has the model resolve the context zone by hand from inlined band tables, a staleness window, a version floor, and a combination rule that `plugins/context-guard/scripts/context-zone.sh` already implements (prompt-audit Group 1b and Group 4). Ship a byte-identical synced copy at `plugins/plugin-quality/scripts/context-zone.sh` with its test, register it in `scripts/cross-plugin-source-registry.txt` with a `sync-context-zone.sh --check` entry, and have the gate and `setup/SKILL.md:28-30` call it. Deferred from the audit as a mechanism change. plugin-quality also adds to F6: two live doc-page titles quoted undated in `agents/auditor.md:117-119`, the `context: fork` and cloud-scoping claims in `references/component-types/skill.md:18-24`, and six dated stamps with no recheck trigger. skill-quality adds to F6: three undated harness claims outside the dated stamp in `check/SKILL.md:160-172`, and the `setup/SKILL.md:16-20` stamp that has no recheck trigger. instruction-placement adds to F6: the undated "other agents resolve nearest-wins" claim in `realign/context/apply-recipes.md:95-97`. context-budget adds to F6: the `v2.1.232` measurement at `audit/SKILL.md:226-228`, the `/doctor` availability and `disableModelInvocation` claim at `audit/SKILL.md:34-36`, the cited-but-undated mechanism claims in `audit/reference/engine.md:25-30` with the dangling "verified version" referent at `:52-53`, and the wall-clock range at `audit/SKILL.md:93`. computer-use adds to F6: the dated surface table in `diagnose/SKILL.md:62-63` and the dated basis in `diagnose/reference/windows-quirks.md:5-6`, both without a recheck trigger. overengineering adds to F6: the undated harness-behavior claim in the gather blocks of all three skills (`audit/SKILL.md:20-23`, `delta/SKILL.md:19-23`, `realign/SKILL.md:19-22`, covered by the one dated record the worktree skill will own) and the undated `/loop` capability claims in `delta/context/recurring-wiring.md:37-38,51-53`.
- F10. Not an audit finding, recorded so it is not mistaken for one: `.claude/hooks/cloud-bootstrap-plugins.test.sh` fails 15 of 32 assertions on this Windows host ("not installed at user scope") with `.claude/cloud-bootstrap.sh` and the suite byte-identical to `origin/main`. The failure is environmental or pre-existing; confirm on CI and file separately if it reproduces there. Same status for `plugins/docs-hygiene/skills/audit-noise/scripts/emit-findings.test.sh` ("tier is looked up as IMPORTANT", "Location is repo-relative") and `plugins/provenance/skills/audit/scripts/list-corpus.test.sh` and `emit-findings.test.sh` ("a directory target lists its markdown"), which fail on this host with their scripts and suites byte-identical to `origin/main`. Same again for `plugins/work-items/skills/onboard-adapter/scripts/generate-adapter.test.sh` case 116, and for the nine eval-case digest assertions in `plugins/planning/tests/interview-defenses.test.sh` (`interview/evals/evals.json` unchanged since the digests were pinned; local jq 1.8.2), and for four Windows temp-path cases in `plugins/instruction-placement/scripts/verify-load.test.sh` (selected by a basename collision on `typescript.md`; the probe and suite are unchanged on this branch). The fleet gather block itself ("the harness runs a skill's whole pre-compute block as one shell invocation") is an undated harness claim in about 55 skills; one dated four-part record on the worktree skill, which owns the mechanism, with the copies pointing at it, clears every site at once. discovery adds six undated claim families across thirteen files (silent preload failure, `AskUserQuestion` and plan-mode tools filtered from non-fork subagents, the Workflow tool absent from subagents, background as the default execution mode, spawns permission-classified before launch); the fix is one dated record per claim in the plugin's `reference/parent-contract.md` with the skills pointing at it. claude-config adds the undated `pre-v2.1.211` boundary at six body sites (the dated owner is `audit-permission-state/reference/criteria.md`), dated-but-triggerless stamps across eight files, the `conflict-scan.sh` precision figures in `conflict-criteria.md`, and the "Fable 5 subpage" pointers in `audit-prompting-postures/reference/postures.md` that need a Fable 5.1 sibling once it exists. discipline adds five files of undated fork-mode harness claims (`sweep-all/SKILL.md`, its two references, `scrutinize-dont-coast/SKILL.md`, `use-your-skills/SKILL.md`). claude-memory adds the undated upstream-issue state at `audit/reference/official-guidance.md:168`. testing adds the xUnit v3 and .NET 10 framework-trap claims (`diagnose/SKILL.md:68`, `diagnose/context/investigate.md:16`, `write/SKILL.md:74`) and the `playwright-cli` version floor in `run-e2e/context/e2e.md:12`. planning also adds two undated harness claims to F6: the agent-teams "experimental, default-off" status in `plan/SKILL.md` and the "cannot read effort or advisor state" claim in `interview/context/session-config.md`.
