# prompt-audit over every skill, 2026-09

Record of running the bundled `/claude-api prompt-audit` (Claude Code 2.1.258) over every skill in this marketplace against Claude Fable 5.1. Written so the unapplied remainder is resumable without re-auditing, so the catalog gaps it exposed are filed, and so the follow-ups ship in the same PR.

## Decay rule

Point-in-time, stamped 2026-09-02. The check is the quoted text, never the status and never the line number. If a finding's quoted source text is still present at or near the cited path, the finding is open. A quote that matches nothing has been applied, superseded, or moved.

## Contents

- [Stated assumptions](#stated-assumptions)
- [Corpus](#corpus)
- [Method](#method)
- [Results by wave](#results-by-wave)
- [Behavioral spot-check](#behavioral-spot-check)
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

One fresh-context subagent per plugin (Claude Fable 5.1 through wave 3b; Claude Opus 5 with the same briefs from wave 3b onward, once the Fable model limit began refusing subagent turns, the target model unchanged) reads the prompt-audit guide and the Fable 5.1 migration sections, audits every in-scope file of that plugin, and writes a report with one row per finding (`file:line`, quoted evidence, pattern row, why obsolete for the target, confidence, action, label, catalog row) and one proposed hunk per finding. The main session reviews each report and records a per-finding decision, then either applies the accepted hunks itself (the lead applied every plugin with about fourteen or fewer accepted hunks by hand from wave 3b onward, thirty-one plugins in all) or dispatches an Opus 5 applier with the same brief (twelve plugins). Either way the applier updates the skill's evals when its body changed, runs `check-skill.sh` on each touched skill, bumps the plugin's patch version with a CHANGELOG line, and commits once per plugin. Eleven setup-only plugins whose single in-scope file the setup lane had already audited took their rows from that lane without a second auditor.

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

<!-- spellchecker:off -->
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
| 2 | debugging | e6ffe3293 | 0.7.4 | F1, F2, F5 to F12, F14 | F3, F4, F13 |
| 2 | bugs | 0cef022b1 | 0.9.9 (above main's 0.9.8; the branch's earlier 0.9.7 entry is renumbered before the PR) | F1 to F8, F10 to F13 (F13 `apply-modified`) | F9, F14 to F17 |
| 2 | testing | e502b6d3c | 0.7.14 | F1 to F4, F9 to F24, F27 (`apply-modified`) | F5 to F8, F25, F26, F28 |
| 2 | discipline | 0bb0e9c1f | 0.13.2 | F1 to F11, setup-lane T1 and T2 (F5, part of F2, F1's `batched-pass.md:76` clause, and T1's `point-dont-copy:49` clause subsumed by neighbouring hunks) | F12 to F15 |
| 3a | playbooks | d7b8900f7 | 0.9.7 | F1 to F12 (F1 `apply-modified`: new `reference/model-adaptation/fable-5-1.md` re-verified against the live Fable 5.1 prompting page on 2026-09-03, two claims attributed to the bundled migration reference instead; fable-5 eval case 4 added) | F13 to F16 |
| 3a | claude-ops | 371004078 | 0.41.12 (main moved to 0.41.10 meanwhile; the branch's earlier 0.41.6 entry is renumbered to 0.41.11 before the PR) | F1 to F25 | F26 to F38 |
| 4b | tdd | a643f73b1 | 0.4.7 | F1 (applied by the lead) | none |
| 4b | domain-driven-design | 53bbeaa37 | 0.3.2 | F1 to F3 (applied by the lead; F1 also corrects the README's install note) | F4 |
| 4b | coupling | 3822d48e7 | 0.1.6 | F1, F2 (applied by the lead) | F3 (fleet gather-block wording), F4 |
| 3a | claude-config | cc5d76494 | 0.40.31 | F1 to F29 (F9 stamps dated 2026-09-04 against the bundled migration reference; F10 hunk 14 keeps the closing sentence its replacement omitted; setup eval 2 reworded) | F30 to F33 |
| 3b | rate-limit-guard | 0763a8c81 | 0.7.26 | F1 (in the synced context-guard source copy), F2, F3, F6, setup-lane T2, T3, T7 (the two synced reference files edited at their registered context-guard source and synced; context-guard's own bump follows in its commit) | F4, F5 |
| 3b | context-guard | de35c27ad | 0.7.32 | F1, F2, F4 to F14 (F7 `apply-modified`; F3 and the synced-file setup-lane hunks landed in 0763a8c81), setup-lane T2, T3, T7, F19 (F11 re-synced both rate-limit-guard copies) | F15 to F17 |
| 3b | guardrails | 0b080653a | 0.31.3 (above main's 0.31.2; the branch's CHANGELOG lacks main's 0.31.0 to 0.31.2 entries until the merge) | F1, setup-lane T2, T4 site 2 | none |
| 2 | discovery | b15ecc2cf | 0.19.4 | F1 to F23, L1, setup-lane F7 and F8 (F8 applied without the version stamp: the sub-agents reference confirms three of the four windows, so setup-lane F20 stays open under F6) | F24 to F26 |
| 3b | skill-quality | dce79fff5 | 0.20.14 (above main's 0.20.13; the branch's earlier 0.20.10 check-3 entry is renumbered before the PR, and the branch CHANGELOG lacks main's 0.20.11 to 0.20.13 entries until the merge) | F1 to F7 | F8, F9 |
| 4b | naming | 9d55edd90 | 0.5.4 | F1 to F5 (applied by the lead) | F6 |
| 4b | evals | 64af28cc1 | 0.2.1 | F1 to F3 (applied by the lead; design eval case 7 asserts the conditional reasoning-then-discard form) | F4 |
| 4b | mcp-tools | 4d957d6bc | 0.3.3 | F1 to F5 (applied by the lead) | F6 |
| 4b | prototype | be7060bd6 | 0.10.4 (above main's 0.10.3; the branch's earlier 0.10.2 entry is renumbered before the PR) | F1 to F7 (applied by the lead; `scripts/allowed-tools-pairing.test.sh` passes) | F8 |
| 3b | autonomy | eab25fd78 | 0.22.25 (above main's 0.22.24; the branch CHANGELOG lacks main's 0.22.21 to 0.22.24 entries until the merge) | F1 to F22, setup-lane T1 sites 12 and 13, T7, F13 to F18 (F15 adds `plugins/autonomy/AGENTS.md` and `CLAUDE.md`; a prior applier's partial edits were reconciled on disk before the commit) | F23 to F29 |
| 3b | plugin-quality | 3d2b4c794, caa46c4d3 | 0.7.9 (above main's 0.7.8; the branch CHANGELOG lacks main's 0.7.7 and 0.7.8 entries until the merge) | F1 to F7, F9 to F18, setup-lane T2, F5, F6 (audit eval case 1 and the setup eval `retirement-r002-overlay-warns-never-silent` reworded; the second commit removes one merged-into-skills aside the first left in the reference index) | F8 (follow-up F19), F19 to F22 |
| 3b | context-budget | 75db56cea | 0.6.22 (above main's 0.6.21; the branch CHANGELOG lacks main's 0.6.18 to 0.6.21 entries until the merge) | F1 to F3 (applied by the lead) | F4 to F9 |
| 3b | instruction-placement | d73d824a2 | 0.11.24 (above main's 0.11.23; the branch CHANGELOG lacks main's 0.11.18 to 0.11.23 entries until the merge) | F1 to F6 (applied by the lead; delta eval case 1 renamed `quiet-run-is-short-and-complete`; the manifest description still says setup verifies "the one thing no other gate can see", out of audit scope, follow-up F2) | F7, F8 |
| 4a | repo-hygiene | 77074974e | 0.10.31 (above main's 0.10.30; the branch's earlier 0.10.27 entry is renumbered before the PR) | F1 to F8 (applied by the lead; `scripts/allowed-tools-pairing.test.sh` and `scripts/lib/cleanup-paths.test.sh` pass) | F9 |
| 3b | improvement | 9f090fb7f | 0.1.8 (above main's 0.1.7; the branch's earlier 0.1.7 entry is renumbered before the PR) | F1 to F8 (applied by the lead) | F9 to F11 |
| 3b | computer-use | 50e9b4733 | 0.1.4 (above main's 0.1.3) | F1 to F9 (applied by the lead; F1 supersedes setup-lane F21; setup eval case 3 reworded) | F10 to F13 |
| 3b | overengineering | 3ee952f2b | 0.3.7 (above main's 0.3.6; the branch's earlier 0.3.6 entry is renumbered before the PR) | F1 to F9 (applied by the lead; F4 `apply-modified` as eval edits to audit cases 10 and 11 and realign case 7; realign case 8 reworded under F6) | F10 to F12 |
| 4b | visualization | cf7c71a51 | 0.5.1 (above main's 0.5.0; the branch CHANGELOG lacks main's 0.5.0 entry until the merge) | F1 to F3 (audited and applied by the lead on 2026-09-05 after the wave-4b auditor died at the session restart) | none |
| 4a | codebase-health | 419decd94 | 0.8.9 (above main's 0.8.7 and the branch's 0.8.8) | F1 to F10 (applied by the lead; F8 supersedes the setup lane's clean verdict on `setup/SKILL.md`) | F11 |
| 4b | mutation-testing | 94e7c256a | 0.3.15 (above main's 0.3.13 and the branch's 0.3.14) | F1 to F10 (applied by the lead) | F11 (follow-up F21) |
| 4a | ai-slop | 820f59b57 | 0.5.10 (above main's 0.5.9; the branch's earlier 0.5.8 entry is renumbered before the PR) | F1 to F11 (applied by the lead; F6 as a move into audit step 6) | F12 |
| 4b | architecture | 249274f96 | 0.6.9 (above main's 0.6.8; the branch's earlier 0.6.8 entry is renumbered before the PR) | F1 to F12 (applied by the lead; F12 as a move into a sixth diagram pattern) | F13, F14 |
| 4a | repo-fleet-hygiene | 946fa0cac | 0.23.18 (above main's 0.23.17; the branch CHANGELOG lacks main's 0.23.16 and 0.23.17 entries until the merge) | F1 to F12, setup-lane F1 and F4 (applied by the lead; audit eval case 14 retargeted to the shipped apply consumer) | F13 to F15 |
| 4a | provenance | d5a24e57b | 0.5.5 (above main's 0.5.4; the branch CHANGELOG lacks main's 0.5.3 and 0.5.4 entries until the merge) | F1 to F13 (applied by the lead; F1 and F11 create `plugins/provenance/skills/audit/AGENTS.md`, indexed in the root `AGENTS.md` in the same commit; setup-lane T1 site 4 was already applied on the branch) | F14 (follow-up F20), F15 |
| 4a | disk-hygiene | fab3fe5f3 | 0.21.7 (above main's 0.21.6; the branch CHANGELOG lacks main's 0.21.3 to 0.21.6 entries until the merge) | F1 to F14, setup-lane T1 sites 2 and 3 (applied by the lead) | F15 (follow-up F6), F16 |
| 4b | wizard | none | unchanged | clean (one skill; the auditor verified every `template.sh` claim against the current file) | F1, F2 |
| 5 | actionlint | bba869139 | 0.8.35 (above main's 0.8.34; the branch CHANGELOG lacks main's 0.8.28 to 0.8.34 entries until the merge) | setup-lane F10 (applied by the lead; the plugin's only in-scope file is `skills/setup/SKILL.md`, audited in full by the setup lane) | setup-lane F25, T9 |
| 5 | bash-format | none | unchanged | clean (only in-scope file is `skills/setup/SKILL.md`, audited in full by the setup lane) | setup-lane T8 |
| 5 | miro | none | unchanged | clean (only in-scope file is `skills/setup/SKILL.md`, audited in full by the setup lane) | setup-lane F22 |
| 5 | biome-format, desktop-notification, eol-normalizer, go-format, markdown-format, powershell-format, ruff-format, typos-format | none | unchanged | clean (each plugin's only in-scope file is `skills/setup/SKILL.md`, listed under the setup lane's clean files) | none |
| 4b | performance | 7bc6ba2ba | 0.1.2 (above main's 0.1.1; the branch CHANGELOG lacks main's 0.1.1 entry until the merge) | F1 to F20 (Opus applier; target eval case 3 and verify eval cases 2, 3, and 7 reworded from run narration to mechanism; every instructive figure kept) | F21 (follow-up F6) |
| 4a | code-tidying | e90a5374a | 0.15.7 (above main's 0.15.6; the branch CHANGELOG lacks main's 0.15.4 to 0.15.6 entries until the merge) | F1 to F22, setup-lane T1 site 1 (Opus applier; F13 `apply-modified` at sites 5 and 6, the CodeScene figure left unrestated under follow-up F6; F12's stamp inherited from the discipline and claude-ops surfaces that carry the same 2026-08-10 basis) | F23 |
| 4b | machine-health | 68309e1ef | 0.12.13 (above main's 0.12.12; the branch CHANGELOG lacks main's 0.12.7 to 0.12.12 entries until the merge) | F1 to F13, setup-lane T2 and F9 (applied by the lead; F4 `apply-modified` keeps the PATH-entry sentence; F8's promotion sentence reworded to "dropping its (future) marker") | F14 to F16 |
| 4b | event-storming | 9128e0e36 | 0.6.8 (above main's 0.6.7) | F1 to F23 (Opus applier; F7 and F13 resolved as prose inside existing files, so the mechanism-change escape did not fire; one F15 replacement word changed to the spelling the typos gate accepts) | none |
| 4a | docs-hygiene | d86a59eed | 0.21.36 (above main's 0.21.35; the branch CHANGELOG lacks main's 0.21.34 and 0.21.35 entries until the merge) | F1 to F20, F22 to F25 (Opus applier; audit-noise eval case 12 and extract-ssot eval case 9 reworded; F1 also corrects the `emit-findings.sh` header comment) | F21, F26, F27 |
| 5 | education | d5931a6ce | 0.10.4 (above main's 0.10.3; the branch CHANGELOG lacks main's 0.10.3 entry until the merge) | F1 to F9 (applied by the lead; setup eval `validates-rendered-quiz-policy-without-settings-edits` names the workspace root) | F10 (follow-up F6) |
| 5 | playwright | 291127ed4 | 0.6.9 (above main's 0.6.8) | F1 to F5 (applied by the lead; F2 keeps 'playwright' and 'E2E test' quoted; F3 keeps the socket-error recovery on the `kill-all` line in `reference/sessions.md`) | F6, F7 (follow-up F6) |
| 5 | kindle-dedrm | 5eee64b9e | 0.7.15 (above main's 0.7.14; the branch CHANGELOG lacks main's 0.7.12 to 0.7.14 entries until the merge) | F1 to F9 (applied by the lead; F8 keeps 'set up Kindle DRM removal' and 'convert Kindle books to EPUB' quoted; the superseded paywall wording in `scripts/check-drift.sh` comments is outside the audit, follow-up F2) | F10, F11 |
| 5 | knowledge | b80ad5588 | 0.13.45 (above main's 0.13.44; the branch CHANGELOG lacks main's 0.13.38 to 0.13.44 entries until the merge) | F1 to F25 (Opus applier; F9 folded into F10's move, which adds `docpage-digest/context/anthropic-docs-queue.md`; F18 appends section 6 to the plugin-level `reference/ingest-deferred-decisions.md` as the move destination the finding names; F4 also drops the fail-open clause in `map-corpus/verification/inventory-format.md`; course-digest eval case 5 stack-neutral; three deletions forced small grammar repairs, listed in the applier report) | F26 (no replacement proposed), F27 (follow-up F6), F28 |
| 5 | songwriting | f39de8e2b | 1.4.23 (above main's 1.4.22; the branch CHANGELOG lacks main's 1.4.22 entry until the merge) | F1 to F10, F9b, setup-lane T4 site 3 with its eval (Opus applier; F4 as its twelve spoke hunks with no ledger note, F8 site 4 resolved by F9b, F9b as a delete because the CHANGELOG already carries the history; ledger row S21 added) | F11, F12 (follow-up F6) |
| 5 | context7 | b159dc98e | 0.5.4 (above main's 0.5.3) | F1 to F11 (applied by the lead; F1 also points `setup/SKILL.md:91` at `context/mcp.md`, superseding the setup lane's withheld F23 site; F5 and F6 keep two and three exact phrases) | F12 |
| 5 | firecrawl | 9a703216a | 0.5.9 (above main's 0.5.8; the branch CHANGELOG lacks main's 0.5.8 entry until the merge) | F1 to F7 (applied by the lead; F1 blanks the seeded sync record for `update.sh --apply` to repopulate; F5 also corrects the Actions list, F8's description half; update eval case 1 says "read-only mode") | F8, F9, F10 |
| 5 | x | 13c0cbcc4 | 0.2.3 (above main's 0.2.2) | F1 to F4, F7 (applied by the lead; F7 is a lead call outside the catalog, replacing a real account name in a shipped example with a placeholder; F4 keeps four exact phrases) | F5 (follow-up F6), F6 |
| 5 | ai-briefing | b07154b5c | 0.7.26 (above main's 0.7.25; the branch CHANGELOG lacks main's 0.7.21 to 0.7.25 entries until the merge) | F1 to F13 (Opus applier; F9 `apply-modified` keeps a version-free drift-trigger row; F6's Role cells filled from each script's header, one left empty where no header exists; F13 applied file-wide, two of its named sites already removed by F7 and F11) | F14 (follow-up F6), F15 |
| 5 | adhd | ccc3d2e04 | 0.4.7 (above main's 0.4.6) | F1, F3, F4 (applied by the lead) | F2 (declined: the five-item list cap is the style skill's own domain-grounded product spec, keep-list 1), F5 (follow-up F6), F6 |
| 5 | dometrain | b7a4413bf | 0.2.10 (above main's 0.2.9; the branch CHANGELOG lacks main's 0.2.9 entry until the merge) | F1 to F8, F12 (applied by the lead; F7 is the setup item the lane did not record; F12 as the same caps normalization) | F9, F10 (follow-up F23), F11 (follow-up F6) |
| 5 | github | 9116abf80 | 0.3.14 (above main's 0.3.13; the branch CHANGELOG lacks main's 0.3.12 and 0.3.13 entries until the merge) | F1 (applied by the lead; the `gh api` write-surface list in advise and audit now carries its verification date, gh version, and recheck trigger) | F2 (keep-list 6), F3 (follow-up F6) |
| 5 | playgrounds | fbf13a922 | 0.1.1 (above main's 0.1.0) | F1, F2 (applied by the lead; F1 keeps four exact phrases) | F3, F4 (follow-up F6) |
<!-- spellchecker:on -->

Notes on the wave-1 and wave-2 commits:

- source-control: `babysit-prs/scripts/tests/test_skill_contract.py` asserts the replacement prose for F2, F23, F35, F36, and F38 instead of the removed markers; no behavior assertion changed. F26 edited `guard_contract.py` claim strings and regenerated `reference/guard-contract.md`.
- session-flow: `keep-going/context/continuation.md` retargets one pointer to the renamed section. The setup-lane items the wave-1 commits left open on paper (session-flow T4 site 1 and F11, source-control T2 at `setup/SKILL.md:119-121`) were checked on 2026-09-05 and are already applied; no second commit was needed.
- work-items: every gate green except `onboard-adapter/scripts/generate-adapter.test.sh` case 116, which fails on this host with unchanged files (follow-up F10).
- claude-memory: audit eval case 10 reworded to the new text.
- planning: `tests/interview-defenses.test.sh` refreshes four section digests the accepted edits changed (Stance, Step 4, the open-question register, the unattended path); every pinned defense line inside them still matches. Nine eval-case digest assertions in that suite fail on this host with `interview/evals/evals.json` unchanged (follow-up F10). `interview/SKILL.md:217` retargets one pointer to the handoff discipline after F19 emptied the flush section. L1 landed on the check flow's step 3 (the `vault_backend` wording), which is where planning carries it.

### check-3 dropped phrases

Each phrase below was a single-quoted trigger in the skill's description at `origin/main` and is absent after the rewrite. The description now names the intent category instead.

- **session-flow** keep-going (9): 'are you stuck', 'carry on', 'continue', 'keep going', 'pick up where you left off', 'poke it', 'resume', 'we got interrupted', 'you got cut off'.
- **source-control** babysit-loop (8): '--merge c3-this-run', 'autopilot', 'babysit loop', 'babysit the PR queue continuously', 'drain the PR queue', 'keep merges flowing', 'run the babysit loop', 'stand up the merge lane'. babysit-prs (7): 'advance all open PRs', 'babysit PRs', 'babysit my PRs', 'babysit worker', 'keep my PRs moving', 'run the PR queue on autopilot', 'watch my open PRs'. setup (8): 'check babysit config', 'configure babysit', 'configure commit convention', 'override the team convention locally', 'set my personal commit convention', 'set up source-control', 'source-control setup', 'what commit format does this repo use'.
- **work-items** track (22): 'add a ticket', 'add a work item', 'add an issue', 'audit stale claims', 'audit work items', 'check overdue recurring items', 'claim a work item', 'close a ticket', 'close a work item', 'close an issue', 'list issues', 'list tickets', 'list work items', 'recheck a recurring item', 'search work items', 'start a ticket', 'start a work item', 'start an issue', 'what work items are open', 'whats due', 'work items dashboard', 'work-item stats'. work (11): 'auto-select a work item', 'do the next thing', 'grab the next ticket', 'grab the next work item', 'pick work', 'start on the backlog', 'what should I work on next', 'work an item', 'work the next issue', 'work the next item', 'work the next ticket'. decompose (15): 'break a plan into tickets', 'create issues from plan', 'decompose into tickets', 'decompose this PRD', 'decompose', 'publish the brief to the tracker', 'publish the spec as a container', 're-decompose', 're-slice', 'reroute the plan', 'spec container', 'split this plan into work items', 'the spec changed, redo the tickets' (the original joined the halves with an em dash), 'turn the plan into tickets', 'vertical-slice this plan'. ship (11): 'close out the container', 'container status', 'drive the spec', 'macro status', 'resume the multi-session effort', 'ship the container', 'ship this spec', 'spec journey', 'whats next in the container', 'where are we on the spec', 'work the spec container'.
- **claude-memory**: none.
- **implementation**, **toolchain**, **verification**, **discovery**, **guardrails**, **claude-ops**, **rate-limit-guard**, **context-guard**, **skill-quality**, **evals**, **mcp-tools**, **autonomy**, **context-budget**, **instruction-placement**, **improvement**, **computer-use**, **codebase-health**, **ai-slop**: none.
- **mutation-testing** audit (4): 'are my tests actually checking this', 'audit test quality', 'mutation score for this change', 'persist the surviving mutants for the fix pass'. principles (6): 'is mutation testing worth it', 'killed vs survived mutant', 'should we gate on mutation score', 'what is mutation testing', 'which mutation operators', 'why is my mutation score low'.
- **architecture** improve (2): 'architecture improvement', 'architecture scan'.
- **repo-fleet-hygiene** audit (6): 'audit repositories', 'cross-repo git cleanup report', 'merged remote branches', 'moved repos', 'renamed GitHub owner', 'repo fleet hygiene'.
- **provenance**, **disk-hygiene**, **actionlint**: none. The clean plugins (wizard and the setup-only wave-5 plugins) have no commit and dropped nothing.
- **performance** goal (2): 'how fast should this be', 'what is a realistic goal'. snapshot (4): 'benchmark this change', 'how noisy is this machine', 'is it actually faster', 'measure this before I change it'. target (2): 'pick a performance target', 'where is the time going' (the report also predicted 'what is slow here', which the description still carries as an unquoted intent and check 3 did not report). verify (3): 'check my benchmark numbers', 'did the optimization actually work', 'double-check before I claim this'.
- **code-tidying** batch-simplify (5): 'simplify everything under <path>', 'simplify everything', 'simplify just this folder', 'simplify my branch changes', 'simplify the whole repo'.
- **machine-health** audit (4): 'check my computer', 'health check', 'run health check', 'workstation audit'.
- **event-storming**, **docs-hygiene**: none.
- **education** eli5 (2): 'I need the visual version', 'draw me how this works'.
- **playwright** playwright (8): 'browser automation', 'check console errors', 'click element', 'fill form', 'mock network', 'record a video', 'take a screenshot', 'test the UI flow'.
- **kindle-dedrm** manage (6): 'check if DeDRM setup is current', 'clean up Kindle DRM tools', 'extract keys from my Kindle library', 'remove DRM from Kindle books', 'sync new Kindle books I bought', 'undo DeDRM setup'.
- **knowledge**, **songwriting**: none.
- **context7** lookup (4): 'check context7 for X', 'how do I configure X', 'latest docs for X', 'whats the API for X'. setup (4): 'add the Context7 MCP server', 'configure context7', 'context7 auth', 'context7 setup'.
- **firecrawl**: none (the description keeps all six quoted phrases and drops only their prose restatements).
- **x** read (3): 'I pasted an X link', 'read this tweet', 'what does this X post say'.
- **ai-briefing**, **adhd**, **dometrain**, **github**: none.
- **playgrounds** use (4): 'explore this parameter space', 'let me tweak parameters and see the result', 'sliders to balance this', 'tune this visually'.
- **plugin-quality** audit (4): 'find bugs/gaps in this plugin', 'find gaps in this plugin', 'is this hook well-designed', 'is this plugin well-designed'.
- **repo-hygiene** clean (9): 'clean caches across all repos', 'clean up my stashes', 'clear build artifacts across all my repos', 'clear build artifacts', 'fresh clone state', 'prune git across the fleet', 'remove caches', 'reset all my repos', 'reset to origin'.
- **overengineering** audit (6): 'enforcement clutter', 'process cruft', 'retire dead automation', 'too many guards', 'what automation can we retire', 'why does this check exist'. delta (4): 'delta since the last run', 'only show me what is new', 'recurring overengineering check', 'weekly automation-cruft check'. realign (5): 'act on the audit findings', 'execute the overengineering findings', 'peel back these hooks', 'retire the automation we agreed to retire', 'start the ablation window'.
- **visualization** visualize (11, against main's 0.5.0 description): 'diagram this', 'draw this', 'make a picture of this', 'render this as', 'show me a diagram of this', 'show me the shape of this', 'sketch this', 'turn this into a visual', 'visualize this', 'visualize', 'what is the best way to show this' (the word "visualize" stays in the description as an unquoted intent verb).
- **naming** name-it-better (3): 'better name', 'come up with a name', 'need a name for'.
- **prototype** explore-directions (5): 'explore design options', 'prototype this screen', 'show me options for this dashboard', 'try a different layout for the settings screen', 'try a few designs'. pressure-test (3): 'does this reducer handle the edge case', 'is this data shape right', 'prototype this logic'.
- **review** fanout (5): 'breadth review', 'fan out review', 'review from every angle', 'review this from all sides', 'run all reviewers'.
- **debugging** debug (4): 'intermittent failure', 'investigate this bug', 'performance regression', 'something is wrong with'.
- **tdd** principles (3): 'TDD cycle', 'what makes a good test', 'when to mock'.
- **claude-config** audit-instructions (4): 'after a model upgrade', 'contradictory instructions', 'instructions the model no longer needs', 'outdated harness claim'. audit-permission-state (4): 'what does auto mode drop', 'what scopes did you check', 'which settings file is my rule coming from', 'why is my allow rule ignored'.
- **playbooks** skill-authoring (7): 'skill authoring', 'skill categories', 'skill design', 'skill structure', 'skill tips', 'skill types', 'write a skill'. fable-5: check 3 reported one span of unquoted description prose between two apostrophes (a parser artifact of the removed Opus-routing clause), not a trigger phrase.
- **discipline** do-your-research (2): 'fact check this', 'fact-check'. do-your-research-deep (1): 'fact-check all these claims'. setup (4): 'configure re-anchor', 'is re-anchor configured', 're-anchor setup', 'set up re-anchor' (the plugin's former name; setup evals 1 to 3 now say "discipline setup").
- **bugs** write (2): '<symbol> gives wrong output when <condition>', 'bug-report this'.
- **testing** audit (8): 'are any of my tests vacuous', 'assertion-free tests', 'audit tests for tautologies', 'find tests that cannot fail', 'gate cant-fail tests in CI', 'persist test-audit findings for the fix pass', 'tautological tests', 'tests pass but prove nothing'. run-e2e (6): 'click through the UI', 'does the app actually work', 'e2e', 'run it end to end', 'smoke test', 'test the app'. write (4): 'add test coverage', 'where should this test go', 'write a unit test for this', 'write tests'.
- **planning** draft-goal-condition (8): '/goal or /loop', 'my /goal is too long / over the limit', 'set up an autonomous goal', 'should this be a routine', 'should this be a workflow', 'turn this into a completion condition', 'what kind of loop is this', 'write a goal condition'. devils-advocate (5): 'argue against this', 'challenge this plan', 'find the holes in this', 'is the incumbent still the right choice', 'reconsider the current approach'.

## Behavioral spot-check

Run 2026-09-05 over the five wave-1 skills the Brief names: session-flow `handoff`, `orchestrate`, and `keep-going`, source-control `commit`, and planning `interview`. For each skill, two blind fresh-context Opus 5 agents invoked the skill on the same fixture, one reading the body and its spokes at the fork point `e69547e3e` and one at the branch tip, neither aware of the other ref and neither allowed a side effect beyond writing its own output file. The fixtures, the agent brief, the ten outputs, and the lead's notes are under `.work/prompt-audit-skills/spot-check/` (gitignored). This is a sanity check on one fixture per skill, not a measurement; behavior measurement stays routed to `claude-config:unhobble` (follow-up F3). What the before-and-after pairs showed:

- **handoff.** Same full-path save-point, same sections, same position panel and rails prompt; the branch-tip run dated every UNVERIFIED tag and used placeholders for the probes it had not run (session id, remote URL) where the fork-point run wrote this session's real values into a fixture worktree that does not exist. Response length grew by about eight percent.
- **orchestrate.** Same armed imperatives, same verbatim brief in rails, and both flagged 24 identical three-line edits as head-count decomposition; the branch-tip run doubled the response by expanding the per-worker spec into a full brief with a mismatch status, stating the verifier's four binary criteria, and listing the commands it must run before filling placeholders. The audit did not shorten this skill's output; it made the spawn spec explicit.
- **keep-going.** Same inventory, same refusal to kill the background task or re-dispatch the applier, same one-sentence goal alignment; the branch-tip run named the summarize-and-stall anti-pattern it was avoiding, reran the read-only test command when completion could not be proven instead of treating ambiguity as alive, and checked push state and for an existing PR before the PR step. Slightly shorter.
- **commit.** Same config probes, ladder resolution, staging preconditions, scoped formatter pass, exec-bit check, subject pre-check, and heredoc commit with the same two trailers; the branch-tip run said it in half the lines by tabulating probe results and per-path checks. No check dropped.
- **interview.** Same survey, slug, ledger-before-asking, recommendation-plus-alternatives shape, and closing probe; the fork-point run invented repository facts the fixture never stated (a mount file, a middleware path, a dependency, a test runner) and built recommendations on them, while the branch-tip run separated the three given facts under a resolved-not-asked heading, marked the one recommendation that depended on an unrun grep as conditional, asked five independent questions and deferred the four dependent ones to round two, and named the gate script it deliberately did not run yet. Longer, because it said what it did not know.

Across the five, no skill lost a step, a gate, or a safety refusal. The direction of change is toward fewer fabricated specifics and more explicit statements of what was and was not verified, with length moving either way.

## Catalog gaps

Findings whose pattern has no row in `plugins/claude-config/skills/audit-instructions/reference/criteria.md`, or that the auditor filed under a row it does not quite match. One line per finding, generated from the reports and decisions by `.work/prompt-audit-skills/gen-record-sections.py`; "withheld" marks the ones that were not applied. Each shape below is a candidate row for the criteria file (follow-up F24).

- **adhd** F2 (`plugins/adhd/skills/shape/SKILL.md:129-136` and `plugins/adhd/skills/clarify/SKILL.md:227`, withheld): Group 1f, "Output-shaping choreography - one pattern, remove every limb": numeric.
- **adhd** F4 (`plugins/adhd/skills/clarify/SKILL.md:150-151`): Group 2, "History narratives: past tense ... past-tense narration of why a rule".
- **ai-slop** F3 (`plugins/ai-slop/skills/audit/reference/rewrite-guide.md:61-62`): Group 2, "The recency trap: one session's stumble encoded as a permanent rule", and.
- **ai-slop** F7 (`plugins/ai-slop/skills/audit/SKILL.md:87-88`): Group 1d, "Migration-relative phrasing: 'X now works differently', 'also counts'".
- **ai-slop** F8 (`plugins/ai-slop/skills/audit/reference/rewrite-guide.md:71-72`): Group 1d, "Migration-relative phrasing".
- **ai-slop** F9 (`plugins/ai-slop/skills/audit/reference/catalog.md:126-127`): Group 1d, "Migration-relative phrasing".
- **ai-slop** F10 (`plugins/ai-slop/skills/audit/reference/catalog.md:140-141`): Group 1d, "Migration-relative phrasing".
- **architecture** F8 (`plugins/architecture/skills/improve/research/deepening/html-report.md:84`): Group 1f, "Output-shaping choreography: numeric output ceilings ('under 120 words'").
- **autonomy** F26 (`plugins/autonomy/reference/trigger-dispatch.md:22-26`, withheld): Group 2, Time-sensitive content (vendor-state claims marked unverified, with a wire-time recheck trigger and no date).
- **autonomy** F27 (`Boris playbook attributions: plugins/autonomy/reference/guardrails.md:13-17; guardrails/work-classes.md:92-95; guardrails/security-review.md:35-37; runner.md:45`, withheld): Group 2, History narratives (provenance paragraphs that assign each idea to its source).
- **bugs** F15 (`plugins/bugs/skills/write/SKILL.md:118 and plugins/bugs/skills/write/context/template.md:43-44, :69-70`, withheld): Group 2, Volatile specifics (an external-API claim with no verification date).
- **claude-config** F15 (`plugins/claude-config/skills/audit-instructions/SKILL.md:2 (description)`): Group 2, Trigger-case enumeration (thirteen phrases, with near-synonym pairs: 'audit instructions' / 'instruction audit').
- **claude-config** F16 (`plugins/claude-config/skills/audit-permission-state/SKILL.md:2 (description)`): Group 2, Trigger-case enumeration (near-synonym pairs: 'what permissions are actually in effect' / 'show me my effective permissions').
- **claude-config** F33 (`Time-relative and machine-specific qualifiers`, withheld): Group 2, Time-sensitive content (idiom-dating only; the convention the first two cite owns the measured platform).
- **claude-ops** F37 (`plugins/claude-ops/skills/audit-install-state/reference/surfaces.md:3-4`, withheld): none in prompt-audit's tables (dated, so the Group 2 "no verification date" row does not match).
- **code-tidying** F6 (`plugins/code-tidying/skills/tidy/reference/exclusions.md:72 and plugins/code-tidying/skills/tidy/lanes/self-update.md:33`): Group 2, "Volatile specifics: hardcoded paths, flags, version numbers, API claims with".
- **code-tidying** F7 (`plugins/code-tidying/skills/tidy/lanes/self-update.md:5-15`): Group 2, "Volatile specifics: hardcoded paths ... skills rot factually as code ships".
- **code-tidying** F16 (`plugins/code-tidying/skills/tidy/SKILL.md:195`): Group 1d, "Migration-relative phrasing: 'X now works differently', 'also counts', 'no".
- **code-tidying** F17 (`plugins/code-tidying/skills/tidy/SKILL.md:82`): Group 1d, "Migration-relative phrasing"; the second sentence describes an in-progress.
- **code-tidying** F23 (`plugins/code-tidying/skills/tidy/SKILL.md:2`, withheld): Group 2, "Trigger-case enumeration": a candidate on shape, but not on provenance.
- **codebase-health** F1 (`plugins/codebase-health/skills/audit/SKILL.md`:232-233): Group 1f, output-shaping choreography (numeric output clamp with a stated operational).
- **computer-use** F11 (`plugins/computer-use/skills/diagnose/SKILL.md:62-63`, withheld): Group 2, Volatile specifics: dated and sourced, but with no recheck trigger, which the repo's four-part record (claim, basis, as-of date).
- **computer-use** F12 (`plugins/computer-use/skills/diagnose/reference/windows-quirks.md:5-6`, withheld): Group 2, Volatile specifics: a dated basis with no recheck trigger.
- **context-budget** F7 (`plugins/context-budget/skills/audit/scripts/fixtures/context-sample.md:3-4`, withheld): Group 2, Time-sensitive content (an as-of stamp with no date); outside the prompt surface (no skill body links the fixture).
- **coupling** F4 (`plugins/coupling/skills/reduce/ (4 files, 59 lines)`, withheld): none in prompt-audit.md.
- **debugging** F5 (`plugins/debugging/skills/debug/SKILL.md:6`): Group 1d, fossil (config that outlived the mechanism it served) and prompt-audit Step 6 "a removal is complete only when everything referencing it goes too".
- **debugging** F13 (`plugins/debugging/skills/debug/reference/ecosystem-debugging.md:11`, withheld): Group 2, volatile specifics (API claims with no verification date).
- **debugging** F14 (`plugins/debugging/skills/debug/reference/ecosystem-debugging.md:3-20 and plugins/debugging/skills/debug/templates/checklist.md:7-12`): none in prompt-audit; house-style item outside this audit's scope.
- **disk-hygiene** F16 (`plugins/disk-hygiene/skills/clean/reference/safety-model.md:303-306`, withheld): Group 2, History narratives (a pinned plugin version number), the same row F4 acts on.
- **docs-hygiene** F11 (`extract-ssot/actions/identify.md:403`): Group 1f, numeric output constraint; and Group 1c "Grader and eval vocabulary" in its pressure-toward-being-scored sense.
- **domain-driven-design** F4 (`plugins/domain-driven-design/skills/curate-language/SKILL.md:8`, withheld): none in prompt-audit.
- **dometrain** F10 (`plugins/dometrain/skills/sync/context/update.md:36-38 and 49-53`, withheld): none.
- **evals** F4 (`plugins/evals/skills/methodology/SKILL.md:2 (and design/SKILL.md:2)`, withheld): Group 2, "Trigger-case enumeration".
- **firecrawl** F1 (`plugins/firecrawl/skills/update/UPSTREAM.md:6-10`): Group 2, "Volatile specifics: hardcoded paths, flags, version numbers, API claims with".
- **firecrawl** F10 (`plugins/firecrawl/skills/firecrawl/SKILL.md:41, 42, 46, 49`, withheld): Group 3, "Tool names in the system prompt; prose lists that shadow the real tool list".
- **github** F1 (`plugins/github/skills/advise/SKILL.md:83-88 and plugins/github/skills/audit/SKILL.md:86-91`): Group 2, "Volatile specifics: hardcoded paths, flags, version numbers, API claims".
- **github** F2 (`plugins/github/skills/advise/SKILL.md:2 and plugins/github/skills/audit/SKILL.md:2`, withheld): Group 2, "Trigger-case enumeration".
- **implementation** F17 (`plugins/implementation/skills/implement/context/bugfix.md:28`, withheld): Group 2, Volatile specifics (an undated count describing an external plugin's contents).
- **improvement** F6 (`plugins/improvement/skills/find/context/hotspots.md:112-128`): Group 4, "An LLM executor for a deterministic plan" (routing, tallying, filtering).
- **machine-health** F16 (`plugins/machine-health/skills/audit/references/shared/discovery-guide.md:11` and `plugins/machine-health/skills/audit/SKILL.md:73`, withheld): considered against Group 1f, "Output-shaping choreography: numeric output ceilings".
- **mutation-testing** F1 (`plugins/mutation-testing/skills/audit/context/suppression.md:25-26`): Group 2, "History narratives: past tense, incident IDs, PR numbers, pinned model names".
- **mutation-testing** F5 (`plugins/mutation-testing/skills/audit/context/persist-findings.md:183`): Group 2, "History narratives: past tense".
- **mutation-testing** F6 (`plugins/mutation-testing/skills/audit/context/persist-findings.md:98`): Group 2, "Volatile specifics".
- **mutation-testing** F7 (`plugins/mutation-testing/skills/principles/SKILL.md:2`): Group 2, "Trigger-case enumeration: description lists of near-synonymous example queries".
- **mutation-testing** F8 (`plugins/mutation-testing/skills/audit/SKILL.md:2`): Group 2, "Trigger-case enumeration".
- **naming** F6 (`plugins/naming/skills/name-it-better/SKILL.md:111-112`, withheld): Group 1a, capitalized emphasis with no adjacent reason.
- **overengineering** F1 (`plugins/overengineering/skills/delta/context/baseline-model.md:23`): Group 1d, Fossils, "Migration-relative phrasing".
- **overengineering** F2 (`plugins/overengineering/skills/delta/SKILL.md:278-279`): Group 1d, Fossils, "Migration-relative phrasing".
- **overengineering** F4 (`plugins/overengineering/skills/audit/evals/evals.json cases 10 and 11; plugins/overengineering/skills/realign/evals/evals.json case 7`): prompt-audit Step 6, "A removal is complete only when everything referencing it goes too: tests asserting the old behavior".
- **overengineering** F6 (`plugins/overengineering/skills/realign/SKILL.md:254-257`): Group 2, "History narratives: past tense, incident IDs, PR numbers, pinned model names".
- **planning** F30 (`plugins/planning/skills/interview/SKILL.md:259`, withheld): none (a spoke pointer filed under the boundary section, where it reads as a "does not do" item).
- **planning** F35 (`plugins/planning/skills/plan/SKILL.md:67`): Group 3, routing text naming a skill not present under `plugins/`; Group 1b adjacent.
- **playgrounds** F2 (`plugins/playgrounds/skills/use/SKILL.md:118-119`): Group 2, "History narratives: past tense, incident IDs, PR numbers, pinned model".
- **playwright** F6 (`plugins/playwright/skills/playwright/SKILL.md:74-77`, withheld): Group 2, row "Volatile specifics: hardcoded paths, flags, version numbers, API".
- **playwright** F7 (`plugins/playwright/skills/playwright/reference/windows-quirks.md:82`, withheld): Group 2, row "Volatile specifics: hardcoded paths, flags, version numbers, API".
- **plugin-quality** F18 (`plugins/plugin-quality/skills/audit/SKILL.md:113-114 (add)`): keep-list 11, "Re-baselining adds text too" (the per-target "Behavioral shifts" sections); Group 4, sub-agent architecture.
- **plugin-quality** F21 (`Dated verification stamps with no recheck trigger (six sites)`, withheld): none in prompt-audit's tables (it names the undated claim as the defect, and these are dated).
- **prototype** F8 (`plugins/prototype/skills/explore-directions/SKILL.md:161-162`, withheld): Group 2, "Verbose SKILL.md" (a sentence the model has to reconcile before it can act on it).
- **rate-limit-guard** F6 (`plugins/rate-limit-guard/skills/setup/SKILL.md:239-240`): none (a lowercase sentence start after a full stop; editing residue, not a dated pattern).
- **review** F20 (`plugins/review/skills/code-review/SKILL.md:47-50`, withheld): none (a sentence fragment; outside prompt-audit's pattern tables).
- **setup-lane** T9 (`Reconfiguration paragraph duplicated verbatim across the fleet`, withheld): none in prompt-audit's tables; keep-list 8 (working redundancy is not cruft).
- **setup-lane** F25 (`plugins/actionlint/skills/setup/SKILL.md:100-106`, withheld): Group 2, Volatile specifics (a version-pinned claim); dated, but with no recheck trigger.
- **testing** F1 (`plugins/testing/skills/write/context/organize.md:49 (and write/context/write.md:121)`): Group 2, "Volatile specifics: hardcoded paths, flags, version numbers" (verified stale).
- **testing** F18 (`plugins/testing/skills/write/context/write.md:28-33`): Group 1c, "Strategy coaching next to task rules": an unconditional approval gate, scoped down only by invocation source.
- **testing** F19 (`plugins/testing/skills/write/context/write.md:62`): Group 1c, "Strategy coaching next to task rules": an invitation to refactor existing code beyond the slice under test.
- **testing** F25 (`plugins/testing/skills/diagnose/SKILL.md:68 (and diagnose/context/investigate.md:16, write/SKILL.md:74)`, withheld): Group 2, "Volatile specifics: ... version numbers, API claims with no verification date".
- **testing** F26 (`plugins/testing/skills/run-e2e/context/e2e.md:12`, withheld): Group 2, "Volatile specifics": an undated version floor.
- **testing** F27 (`plugins/testing/skills/diagnose/context/investigate.md:55-60 (and loop.md:111-116, plan/SKILL.md:120-125, run-e2e/context/e2e.md:154-159, write/context/organize.md:61-66, write/context/write.md:151-157)`): The brief's routing rule: a sibling reference naming a skill that does not exist under `plugins/`.
- **toolchain** F14 (`plugins/toolchain/skills/check/context/dotnet.md:52`, withheld): Group 2, Volatile specifics; dated, but with no recheck trigger.
- **toolchain** F15 (`plugins/toolchain/skills/check/context/go.md:38`, withheld): Group 2, Volatile specifics (a verification stamp with a toolchain version but no date and no recheck trigger).
- **verification** F5 (`plugins/verification/skills/measure/context/metrics.md:11-20 (add after the table)`): Group 4, An LLM executor for a deterministic plan (a count is a computation whose inputs fully determine its output); Group 1b.
- **verification** F10 (`plugins/verification/skills/measure/context/metrics.md:90-96 and plugins/verification/skills/measure/context/performance.md:61-68`): the brief's routing rule: a sibling reference is flagged when it names a skill that does not exist in `plugins/`.
- **wizard** F1 (`plugins/wizard/skills/generate/SKILL.md:99-104`, withheld): Group 1a, pressure language.

## Withheld findings

Low-confidence and `flag` items, reported but not applied. Grouped by plugin, one line per finding: id, location, the pattern row the auditor cited, the auditor's confidence, and the lead's disposition, generated from the reports and decisions by `.work/prompt-audit-skills/gen-record-sections.py`. The setup-lane group holds the cross-cutting setup-skill findings that no single plugin owns.

- **adhd** (3):
  - F2 (`plugins/adhd/skills/shape/SKILL.md:129-136` and `plugins/adhd/skills/clarify/SKILL.md:227`), Group 1f, "Output-shaping choreography - one pattern, remove every limb": numeric; medium; declined by the lead: the five-item cap is this style skill's own product spec, grounded in the working-memory fact at line 39, not a clamp written against an older model's verbosity; keep-list 1.
  - F5 (`plugins/adhd/skills/clarify/SKILL.md:143-156, 191-193`), Group 2, "Volatile specifics: hardcoded paths, flags, version numbers, API claims"; low; withheld; follow-up F6.
  - F6 (`plugins/adhd/skills/clarify/SKILL.md:2` and `plugins/adhd/skills/shape/SKILL.md:2`), Group 2, "Trigger-case enumeration: description lists of near-synonymous example"; low; withheld, low confidence.
- **ai-briefing** (2):
  - F14 (`plugins/ai-briefing/skills/generate/references/slide-generation.md:215, :247`), Group 2, Volatile specifics (a command form and a harness command named as bare fact); low; withheld; follow-up F6 (`/reload-plugins` does exist in the current Claude Code build; the record notes it).
  - F15 (`plugins/ai-briefing/skills/generate/references/slide-generation.md:99, :157, :165; build-pipeline.md:107`), Group 2, The recency trap (one window's news encoded as a permanent illustration); low; withheld, low confidence.
- **ai-slop** (1):
  - F12 (`plugins/ai-slop/skills/audit/reference/catalog.md:1-1098`), Group 2, "Verbose SKILL.md explaining things the model already knows" (signal row); low; withheld, low confidence; owned by `docs-hygiene:audit-progressive-disclosure`.
- **architecture** (2):
  - F13 (`plugins/architecture/skills/improve/SKILL.md:25-28`), Group 2, "Volatile specifics"; low; withheld; follow-up F6.
  - F14 (`plugins/architecture/skills/improve/SKILL.md:40`), Group 1c, "Padding: repetition as reinforcement"; low; withheld; keep-list 10.
- **autonomy** (7):
  - F23 (`plugins/autonomy/skills/setup/SKILL.md:267; plugins/autonomy/skills/setup/context/prerequisite-resolution-slice.md:38-39; plugins/autonomy/reference/prerequisite-resolution.md:86-88`), Group 2, Volatile specifics (a harness-capability claim stated three times with no verification date or recheck trigger); low; withheld; follow-up F6.
  - F24 (`plugins/autonomy/reference/telemetry.md:14-15, :22, :69-70`), Group 2, Volatile specifics (undated empirical harness claims and an upstream-status claim); low; withheld; follow-up F6.
  - F25 (`plugins/autonomy/reference/runner/escalation.md:140-152`), Group 2, Volatile specifics (harness-capability claims, "today", no date); low; withheld; follow-up F6.
  - F26 (`plugins/autonomy/reference/trigger-dispatch.md:22-26`), Group 2, Time-sensitive content (vendor-state claims marked unverified, with a wire-time recheck trigger and no date); low; withheld, low confidence.
  - F27 (`Boris playbook attributions: plugins/autonomy/reference/guardrails.md:13-17; guardrails/work-classes.md:92-95; guardrails/security-review.md:35-37; runner.md:45`), Group 2, History narratives (provenance paragraphs that assign each idea to its source); low; withheld, low confidence.
  - F28 (`plugins/autonomy/reference/runner.md:12-13 and :33`), Group 2, History narratives (a planning-era tier label, `T4`, defined nowhere in the plugin); low; withheld, low confidence.
  - F29 (`plugins/autonomy/reference/autonomous-pipeline-reminder.md:29-66 (out of scope)`), Keep-list 11, Re-baselining adds text too; Group 1d, Fossils (a locally reworded prompting-guide block); low; out of audit scope; follow-up F18.
- **bugs** (5):
  - F9 (`plugins/bugs/skills/write/SKILL.md:20-22`), Group 2, History narratives (a rationale for how a fixed command came to be shaped, addressed to whoever might edit it); medium; fleet decision: the "pipe is the bound" paragraph is kept fleet-wide.
  - F14 (`plugins/bugs/skills/scan/SKILL.md:119-120`), Group 2, Volatile specifics (a figure stated as bare fact with no source or recheck trigger); low; withheld, low confidence.
  - F15 (`plugins/bugs/skills/write/SKILL.md:118 and plugins/bugs/skills/write/context/template.md:43-44, :69-70`), Group 2, Volatile specifics (an external-API claim with no verification date); low; withheld, low confidence.
  - F16 (`plugins/bugs/skills/scan/SKILL.md:22-25 and plugins/bugs/skills/write/SKILL.md:24-27`), Group 2, Volatile specifics (a harness-behavior claim with no verification date); low; withheld; follow-up F6 (one dated record on the fleet gather block).
  - F17 (`plugins/bugs/skills/scan/SKILL.md:231-246 and plugins/bugs/skills/write/SKILL.md:144-150`), Group 1c, Padding (repetition as reinforcement; near-duplicate sentences across sections); low; withheld; keep-list 10.
- **claude-config** (4):
  - F30 (Undated `pre-v2.1.211` harness-version claims), Group 2, Volatile specifics (a harness version boundary stated as bare fact with no verification date in the bodies); medium (pattern match); action withheld to `flag`; withheld; follow-up F6.
  - F31 (`plugins/claude-config/skills/audit-instructions/reference/conflict-criteria.md:532-533, :540-547`), Group 2, Volatile specifics (an undated local measurement); low; withheld; follow-up F6 (measured figure).
  - F32 (`Dated stamps with no recheck trigger, and undated verification notes`), Group 2, Volatile specifics; low; withheld; follow-up F6.
  - F33 (`Time-relative and machine-specific qualifiers`), Group 2, Time-sensitive content (idiom-dating only; the convention the first two cite owns the measured platform); low; withheld, low confidence.
- **claude-memory** (1):
  - F12 (`plugins/claude-memory/skills/audit/reference/official-guidance.md:168`), Group 2, "Volatile specifics ... with no verification date"; low; withheld; follow-up F6.
- **claude-ops** (13); shared note: withheld; F26, F28, F29, F30, F31, F32, F33, F34, F37 join follow-up F6 (undated harness and upstream claims); F27 and F35 join F6's measured-figure note; F36 and F38 are keep-list 8 and 10:
  - F26 (`plugins/claude-ops/skills/audit-install-state/SKILL.md:48-53`), Group 2, Volatile specifics (harness claims with no verification date or recheck trigger); low; see the shared note.
  - F27 (`plugins/claude-ops/skills/audit-install-state/SKILL.md:223-224`), Group 2, Volatile specifics (a measured figure with no date or trigger); low; see the shared note.
  - F28 (`plugins/claude-ops/skills/audit-native-overlap/SKILL.md:286-289`), Group 2, Volatile specifics (undated harness examples); low; see the shared note.
  - F29 (`plugins/claude-ops/skills/inventory/SKILL.md:210-216`), Group 2, Volatile specifics ("Verified" with no date); low; see the shared note.
  - F30 (`plugins/claude-ops/skills/changelog/SKILL.md:167 and context/read-actions.md:9-13`), Group 2, Volatile specifics (harness behavior with no verification date); low; see the shared note.
  - F31 (`plugins/claude-ops/skills/lanes/SKILL.md:92-104, :214-221 and context/refresh.md:68-80`), Group 2, Volatile specifics (harness claim with a doc link but no verification date), stated three times; low; see the shared note.
  - F32 (`plugins/claude-ops/skills/lanes/SKILL.md:189-193, :223-235 and context/refresh.md:10-11`), Group 2, Volatile specifics ("verified" and "confirmed on this machine" with no date or CLI version); low; see the shared note.
  - F33 (`plugins/claude-ops/skills/observability/SKILL.md:150-151`), Group 2, Volatile specifics (two harness-defect claims with no date, issue, or trigger); Group 1d model-version workaround shape; low; see the shared note.
  - F34 (`plugins/claude-ops/skills/observability/context/read-routing.md:75 and plugins/context/sync.md:122-125`), Group 2, Volatile specifics (upstream issue state stated without a date); low; see the shared note.
  - F35 (`plugins/claude-ops/skills/observability/context/operator-setup-retention.md:15-16 and context/data-sources.md:251`), Group 2, Volatile specifics (measured figures with no date or trigger); low; see the shared note.
  - F36 (`plugins/claude-ops/skills/audit-performance/SKILL.md:177-193 and audit-skill-visibility/SKILL.md:208-211, :215-217`), Group 1c, Padding (repetition as reinforcement; near-duplicate sentences across sections); low; see the shared note.
  - F37 (`plugins/claude-ops/skills/audit-install-state/reference/surfaces.md:3-4`), none in prompt-audit's tables (dated, so the Group 2 "no verification date" row does not match); low; see the shared note.
  - F38 (`plugins/claude-ops/skills/setup/SKILL.md:80-83 and :85-87`), Group 1c, Padding (near-duplicate sentences across sections); low; see the shared note.
- **code-tidying** (1):
  - F23 (`plugins/code-tidying/skills/tidy/SKILL.md:2`), Group 2, "Trigger-case enumeration": a candidate on shape, but not on provenance; low; withheld, low confidence; keep-list 6.
- **codebase-health** (1):
  - F11 (`plugins/codebase-health/skills/audit/SKILL.md`:25-28), Group 2, brittle skill files, "API claims with no verification date"; low; withheld; follow-up F6.
- **computer-use** (4):
  - F10 (`plugins/computer-use/skills/diagnose/SKILL.md:2`), Group 2, Trigger-case enumeration (partial match); low; withheld, low confidence.
  - F11 (`plugins/computer-use/skills/diagnose/SKILL.md:62-63`), Group 2, Volatile specifics: dated and sourced, but with no recheck trigger, which the repo's four-part record (claim, basis, as-of date); low; withheld; follow-up F6 (dated stamp, no recheck trigger).
  - F12 (`plugins/computer-use/skills/diagnose/reference/windows-quirks.md:5-6`), Group 2, Volatile specifics: a dated basis with no recheck trigger; low; withheld; follow-up F6 (dated stamp, no recheck trigger).
  - F13 (`plugins/computer-use/skills/diagnose/SKILL.md:76-87`), Group 1c, Padding (repetition across sections); low; withheld; keep-list 10.
- **context-budget** (6):
  - F4 (`plugins/context-budget/skills/audit/SKILL.md:226-228`), Group 2, Volatile specifics (a version-pinned harness-behavior claim with no verification date and no recheck trigger); low; withheld; follow-up F6.
  - F5 (`plugins/context-budget/skills/audit/SKILL.md:34-36`), Group 2, Volatile specifics (an undated claim about a bundled skill's availability and frontmatter); low; withheld; follow-up F6.
  - F6 (`plugins/context-budget/skills/audit/reference/engine.md:25-30 (and :52-53)`), Group 2, Volatile specifics (API claims carrying citations but no verification date or recheck trigger); low; withheld; follow-up F6.
  - F7 (`plugins/context-budget/skills/audit/scripts/fixtures/context-sample.md:3-4`), Group 2, Time-sensitive content (an as-of stamp with no date); outside the prompt surface (no skill body links the fixture); low; withheld; outside the prompt surface.
  - F8 (`plugins/context-budget/skills/audit/SKILL.md:24-26, :51, :86`), Group 1c, Padding (repetition as reinforcement; the same constraint restated across sections); low; withheld; keep-list 8 and 10.
  - F9 (`plugins/context-budget/skills/audit/SKILL.md:93`), Group 2, Volatile specifics (a wall-clock range with no date, machine class, or recheck trigger); low; withheld; follow-up F6.
- **context-guard** (3):
  - F15 (plugins/context-guard/skills/setup/SKILL.md:37-135 (`check` steps 1, 2, 4, 5)), Group 4, An LLM executor for a deterministic plan; medium; recorded as follow-up F17: moving the probes into a `## Pre-computed context` block is a mechanism change gated by `scripts/check-skill-precompute-compose.sh` and the worktree guard's `$`-expansion rule, not an audit hunk.
  - F16 (`Undated harness-capability claims in four sites`), Group 2, Volatile specifics (harness settings keys and behavior stated as bare fact with no verification date); low; withheld; follow-up F6.
  - F17 (`plugins/context-guard/reference/reader-contract.md:383-391`), Group 2, History narratives (pinned model names in provenance prose); dated, but with no recheck trigger; low; withheld; follow-up F6.
- **context7** (1):
  - F12 (`plugins/context7/skills/lookup/SKILL.md:26 versus context/update.md:52`), Group 1a, the `Default to [tool]` row; read against a convention this plugin states about; low; withheld, low confidence.
- **coupling** (2):
  - F3 (`plugins/coupling/skills/reduce/SKILL.md:25-28`), Group 1c, "Padding: ... asides get applied where they don't fit"; also Group 2; medium; fleet decision: the gather-block wording is settled fleet-wide and is not rewritten per plugin.
  - F4 (`plugins/coupling/skills/reduce/ (4 files, 59 lines)`), none in prompt-audit.md; low; withheld; house style owned by `ai-slop:audit`.
- **debugging** (3):
  - F3 (`plugins/debugging/skills/debug/SKILL.md:25-28`), Group 1d, migration-relative phrasing ("rather than pre-compute lines" is a diff against the previous prompt version the model never saw); medium; fleet decision: the gather-block sentence "Keep these as separate body Bash calls rather than pre-compute lines: ..." is the settled fleet wording (a structural contrast, not a version diff); do not rewrite it per plugin.
  - F4 (`plugins/debugging/skills/debug/SKILL.md:21-23`), Group 2, verbose SKILL.md explaining things the model already knows (every paragraph must justify its token cost); medium; fleet decision: the one-sentence "The pipe is the bound and belongs in the command" form is kept fleet-wide (it stops a read-time cap from replacing the pipe); source-control already applied that form.
  - F13 (`plugins/debugging/skills/debug/reference/ecosystem-debugging.md:11`), Group 2, volatile specifics (API claims with no verification date); low; withheld, low confidence.
- **discipline** (4):
  - T3 (`Gotchas bullets that restate rules already in the body`), Group 1c, Padding (repetition as reinforcement; near-duplicate sentences across sections); low; withheld; keep-list 10.
  - T4 (`"Does not fabricate a finding" recap of the shared method's non-negotiable`), Group 1c, Padding (repetition as reinforcement across files); signal `do not hallucinate`; low; withheld, low confidence.
  - T5 (`Undated harness fork-mode claims`), Group 2, Volatile specifics (harness API claims with a source but no verification date or recheck trigger); low; withheld; follow-up F6.
  - F12 (`plugins/discipline/skills/sweep-all/SKILL.md:176-179`), Group 2, Volatile specifics (a measured figure from one run, no date, no recheck trigger); low; withheld, low confidence.
- **discovery** (3):
  - F24 (`Undated harness-behavior claims stated as bare fact (multiple files)`), Group 2, Volatile specifics (API and harness claims with no verification date); low; withheld; follow-up F6.
  - F25 (`plugins/discovery/skills/explore/reference/dispatch.md:166-187`), Group 2, Volatile specifics; low; withheld, low confidence.
  - F26 (`plugins/discovery/agents/explorer.md, agents/researcher.md, agents/intent-tracer.md (Group 4 roster)`), Group 4, Redundant specialist sub-agents (roster check); low; withheld, low confidence.
- **disk-hygiene** (2):
  - F15 (`Undated harness-version claims (four sites)`), Group 2, Volatile specifics (harness version numbers and API claims with no verification date); low; withheld; follow-up F6.
  - F16 (`plugins/disk-hygiene/skills/clean/reference/safety-model.md:303-306`), Group 2, History narratives (a pinned plugin version number), the same row F4 acts on; low; withheld, low confidence; keep-list 1.
- **docs-hygiene** (3):
  - F21 (`extract-ssot/actions/batch.md:35 and 281`), Group 2, "Volatile specifics"; low; withheld; follow-up F6.
  - F26 (`extract-ssot/SKILL.md:27, extract-ssot/context/anti-patterns.md:129, extract-ssot/context/decision-framework.md:27-30, 56, 59`), Group 2, "Volatile specifics"; low; withheld; follow-up F6.
  - F27 (`audit-encapsulation/context/public-surface-contract.md:5`), Group 2, "Volatile specifics"; low; withheld; follow-up F6.
- **domain-driven-design** (1):
  - F4 (`plugins/domain-driven-design/skills/curate-language/SKILL.md:8`), none in prompt-audit; low; withheld; house style owned by `ai-slop:audit`.
- **dometrain** (3):
  - F9 (`plugins/dometrain/skills/grounding/SKILL.md:2`), Group 2, Trigger-case enumeration (partial match only); low; withheld, low confidence.
  - F10 (`plugins/dometrain/skills/sync/context/update.md:36-38 and 49-53`), none; low; withheld; recorded as follow-up F23 (a documented maintainer command resolves `${CLAUDE_PLUGIN_ROOT}` to the installed cache the next paragraph forbids writing).
  - F11 (`plugins/dometrain/skills/setup/SKILL.md:20-26`), Group 2, Volatile specifics (an API claim with no verification date); low; withheld; follow-up F6.
- **education** (1):
  - F10 (`plugins/education/skills/teach/SKILL.md:86 (the harness claim, not the tracker ref)`), Group 2, Volatile specifics (a harness-behavior claim with no verification date); low; withheld; follow-up F6.
- **evals** (1):
  - F4 (`plugins/evals/skills/methodology/SKILL.md:2 (and design/SKILL.md:2)`), Group 2, "Trigger-case enumeration"; low; withheld, low confidence.
- **event-storming**: none.
- **firecrawl** (3):
  - F8 (`plugins/firecrawl/skills/firecrawl/SKILL.md:92 (with lines 2 and 3)`), Group 2, "Volatile specifics: hardcoded paths, flags, version numbers"; low; withheld, low confidence; the description half lands with F5.
  - F9 (`plugins/firecrawl/skills/firecrawl/context/commands.md:120`), Group 2, "duplicated info across SKILL.md and reference files"; low; withheld, low confidence; keep-list 8.
  - F10 (`plugins/firecrawl/skills/firecrawl/SKILL.md:41, 42, 46, 49`), Group 3, "Tool names in the system prompt; prose lists that shadow the real tool list"; low; withheld, low confidence.
- **github** (2):
  - F2 (`plugins/github/skills/advise/SKILL.md:2 and plugins/github/skills/audit/SKILL.md:2`), Group 2, "Trigger-case enumeration"; low; withheld, low confidence; keep-list 6.
  - F3 (`plugins/github/skills/setup/SKILL.md:62`), Group 2, "Volatile specifics", read as a harness-substitution claim; low; withheld; follow-up F6.
- **guardrails**: none.
- **implementation** (6):
  - F15 (`plugins/implementation/skills/implement/SKILL.md:2`), Group 2, Trigger-case enumeration (eight quoted phrases); low; withheld, low confidence.
  - F16 (`plugins/implementation/agents/implementer.md:26-51 and plugins/implementation/agents/phase-verifier.md:23-45`), none in prompt-audit's tables; low; withheld; candidate for an instruction-placement pass (agent-file rationale sections).
  - F17 (`plugins/implementation/skills/implement/context/bugfix.md:28`), Group 2, Volatile specifics (an undated count describing an external plugin's contents); low; withheld, low confidence.
  - F18 (`plugins/implementation/skills/implement-dispatch/SKILL.md:43, 116, 117`), none in prompt-audit's tables (verified true for this repo: both checks run in `.github/workflows/ci.yml`); low; withheld, low confidence.
  - F19 (`plugins/implementation/skills/implement/SKILL.md:18, 20`), Group 2, Volatile specifics (a harness-behavior claim about which command shapes a worktree-isolated session accepts); low; withheld; a trailing `\| head` on a git command is accepted by worktree isolation (the worktree skill states it and this session confirms it), so the concern does not hold.
  - F20 (`plugins/implementation/skills/implement/context/refactor.md:12`), none in prompt-audit's tables; low; withheld, low confidence.
- **improvement** (3):
  - F9 (`plugins/improvement/skills/find/context/ci-health.md:32-36, :40-41; skills/find/SKILL.md:235-237; skills/find/context/unattended.md:74-75`), Group 2, Volatile specifics ("hardcoded paths, flags, version numbers, API claims"); medium (pattern match); action withheld to `flag`; withheld; follow-up F6.
  - F10 (`plugins/improvement/skills/find/SKILL.md:227-241`), Group 1c, Padding (repetition as reinforcement); low; withheld; keep-list 10.
  - F11 (`plugins/improvement/skills/find/SKILL.md:2`), Group 2, Trigger-case enumeration (description lists of near-synonymous example); low; withheld, low confidence.
- **instruction-placement** (2):
  - F7 (`Gotchas sections that restate rules already in the body (four skills)`), Group 1c, Padding (repetition as reinforcement; near-duplicate sentences across sections); low; withheld; keep-list 10.
  - F8 (`plugins/instruction-placement/skills/realign/context/apply-recipes.md:95-97`), Group 2, Volatile specifics (an undated claim about how other harnesses resolve a file, with no verification record); low; withheld; follow-up F6.
- **kindle-dedrm** (2):
  - F10 (`plugins/kindle-dedrm/skills/manage/SKILL.md:143`), Group 1a, "Pressure language", with Group 1c "repetition as reinforcement"; low; withheld, low confidence; keep-list 8.
  - F11 (`plugins/kindle-dedrm/skills/manage/references/troubleshooting.md:246-248`), none; low; withheld; subsumed by F3.
- **knowledge** (3):
  - F26 (`Trigger-case enumeration in five skill descriptions`), Group 2, Trigger-case enumeration; low; withheld, low confidence; no replacement proposed (check 3 is advisory, so the gate does not block a later consolidation).
  - F27 (`Undated external version floors`), Group 2, Volatile specifics (version numbers with no verification date); low; withheld; follow-up F6.
  - F28 (`Rule bodies restated across docpage-digest's two Phase 4 spokes`), Group 2, Time-sensitive content (duplicated info across SKILL.md and reference); low; withheld, low confidence; keep-list 8.
- **machine-health** (3):
  - F14 (`plugins/machine-health/skills/setup/SKILL.md:2`), Group 2, "Trigger-case enumeration"; low; withheld, low confidence.
  - F15 (`plugins/machine-health/skills/audit/references/windows/remediation-policy.md:67`), Group 1a, "Pressure language"; the signal is emphasis with no adjacent "because"; low; withheld, low confidence; the prohibition stays.
  - F16 (`plugins/machine-health/skills/audit/references/shared/discovery-guide.md:11` and `plugins/machine-health/skills/audit/SKILL.md:73`), considered against Group 1f, "Output-shaping choreography: numeric output ceilings"; low; withheld; keep-list 4.
- **mcp-tools** (1):
  - F6 (`plugins/mcp-tools/skills/audit/reference/checklist.md:38, 105, 106`), Group 2, "Volatile specifics: hardcoded paths, flags, version numbers, API claims with no verification date"; medium; withheld; follow-up F6.
- **mutation-testing** (1):
  - F11 (`plugins/mutation-testing/skills/setup/SKILL.md:80-89`), Group 1b, "Inline lookup tables, point systems, arithmetic rubrics the model must compute → Data in files or tool results"; medium; recorded as follow-up F21 in the record (a new lint script and test).
- **naming** (1):
  - F6 (`plugins/naming/skills/name-it-better/SKILL.md:111-112`), Group 1a, capitalized emphasis with no adjacent reason; low; withheld, low confidence.
- **overengineering** (3):
  - F10 (`plugins/overengineering/skills/audit/SKILL.md:20-23, plugins/overengineering/skills/delta/SKILL.md:19-23, plugins/overengineering/skills/realign/SKILL.md:19-22`), Group 2, "Volatile specifics"; low; withheld; follow-up F6.
  - F11 (`plugins/overengineering/skills/delta/context/recurring-wiring.md:37-38 and 51-53`), Group 2, "Volatile specifics"; medium; withheld; follow-up F6.
  - F12 (`plugins/overengineering/skills/audit/SKILL.md:92-93 and 142-144; plugins/overengineering/skills/audit/context/surface-walk.md:95-97; plugins/overengineering/skills/delta/context/recurring-wiring.md:24-25`), model-migration.md, "Migrating to Claude Fable 5.1", Behavioral shifts, "Rare: context anxiety"; low; withheld, low confidence.
- **performance** (1):
  - F21 (`plugins/performance/skills/snapshot/SKILL.md:94-96`), Group 2, "Volatile specifics: hardcoded paths, flags, version numbers, API claims with no verification date"; low; withheld; follow-up F6.
- **planning** (6):
  - F30 (`plugins/planning/skills/interview/SKILL.md:259`), none (a spoke pointer filed under the boundary section, where it reads as a "does not do" item); low; withheld, low confidence.
  - F31 (`plugins/planning/skills/plan/SKILL.md:198 and 206`), Group 2, Volatile specifics (harness-capability status stated as bare fact, undated); low; withheld; follow-up F6 (undated harness claims).
  - F32 (`plugins/planning/skills/interview/context/session-config.md:103-108`), Group 2, Volatile specifics (harness-capability claim, undated); low; withheld; follow-up F6.
  - F33 (`plugins/planning/skills/wayfind/SKILL.md:20`), Group 4, Request-building code disagreeing with its own prose contract; low; withheld; follow-up F9 (wayfind pre-compute coerces a non-string container label its own doc forbids).
  - F34 (`plugins/planning/skills/wayfind/SKILL.md:2, 90, 189, 200`), Group 3, routing text naming a plugin rather than an invocable skill; low; withheld, low confidence.
  - F36 (`plugins/planning/skills/prd/SKILL.md:58 and 92`), Group 1c, Padding (near-duplicate sentences across sections, two differently worded canned messages for one event); low; withheld, low confidence.
- **playbooks** (4):
  - F13 (`skills/fable-5/context/calibration.md:66-69`), Group 2, volatile specifics (binary-registry internals), dated and triggered in the correct form; low; withheld, low confidence.
  - F14 (`skills/fable-5/context/orchestration.md:97`), Group 2, volatile specifics (restated pricing ratio and TTL), dated but with no recheck trigger of their own; low; withheld; follow-up F6 (missing recheck trigger on the cache-pricing stamp).
  - F15 (`skills/boris/SKILL.md:58,133` and `skills/boris/reference/orchestration.md:92-106`), Group 2, pinned model names; judged under the brief's per-model-doctrine criterion; low; withheld; follow-up F13 (boris re-sync).
  - F16 (`reference/model-adaptation/opus-5.md:62-63,207-208,243-246`), Group 2, brittle skill files (maintainer bookkeeping in a model-facing chapter); I13 for the citation; low; withheld; follow-up F8 (non-loading citation) and a maintainer note.
- **playgrounds** (2):
  - F3 (`plugins/playgrounds/skills/use/SKILL.md:72-73`), Group 2, "Volatile specifics: hardcoded paths, flags, version numbers, API claims"; low; withheld; follow-up F6 (case 3 quotes the command, unchanged).
  - F4 (`plugins/playgrounds/skills/use/SKILL.md:53-56`), Group 2, "Volatile specifics: hardcoded paths, flags, version numbers, API claims"; low; withheld; follow-up F6.
- **playwright** (2):
  - F6 (`plugins/playwright/skills/playwright/SKILL.md:74-77`), Group 2, row "Volatile specifics: hardcoded paths, flags, version numbers, API"; low; withheld; follow-up F6.
  - F7 (`plugins/playwright/skills/playwright/reference/windows-quirks.md:82`), Group 2, row "Volatile specifics: hardcoded paths, flags, version numbers, API"; low; withheld; follow-up F6 (setup/SKILL.md:34-40 consumes the claim).
- **plugin-quality** (5):
  - F8 (`plugins/plugin-quality/skills/audit/SKILL.md:58-92 (and skills/setup/SKILL.md:28-30)`), Group 1b, "Inline lookup tables, point systems, arithmetic rubrics the model must compute" (replacement: data in files or tool results); medium; recorded as follow-up F19 in the record: a synced copy of `context-zone.sh` plus its test, a registry entry, and a sync script is a mechanism change, not an audit hunk. Leave `:58-92` and `setup/SKILL.md:28-30` as they are.
  - F19 (`plugins/plugin-quality/agents/auditor.md:117-119`), Group 2, Volatile specifics (two live documentation page titles stated as bare fact with no date; they illustrate the "same subject"); low; withheld; follow-up F6.
  - F20 (`plugins/plugin-quality/skills/audit/references/component-types/skill.md:18-20 and :22-24`), Group 2, Volatile specifics (harness-capability claims with no verification date or recheck trigger); low; withheld; follow-up F6.
  - F21 (`Dated verification stamps with no recheck trigger (six sites)`), none in prompt-audit's tables (it names the undated claim as the defect, and these are dated); low; withheld; follow-up F6 (dated stamps with no recheck trigger).
  - F22 (`plugins/plugin-quality/agents/auditor.md:5`), none in prompt-audit's tables (it does not error on the target and is not a sampling parameter); low; withheld, low confidence; `effort: high` is a fleet convention.
- **prototype** (1):
  - F8 (`plugins/prototype/skills/explore-directions/SKILL.md:161-162`), Group 2, "Verbose SKILL.md" (a sentence the model has to reconcile before it can act on it); low; withheld, low confidence.
- **provenance** (2):
  - F14 (`plugins/provenance/skills/audit/SKILL.md:2, :82, :227 versus reference/rubric.md:297`), Group 1c, Padding (duplicated wordings of one rule that the model must reconcile); low; withheld; recorded as follow-up F20 in the record (script and test change).
  - F15 (`plugins/provenance/skills/audit/SKILL.md:2`), Group 2, Trigger-case enumeration (a description listing near-synonymous example); low; withheld, low confidence.
- **rate-limit-guard** (2):
  - F4 (`plugins/rate-limit-guard/skills/setup/reference/unwrap-before-compose.md:11-109 (and SKILL.md:109-200, which drives it)`), Group 4, An LLM executor for a deterministic plan (a call whose inputs fully determine its output executed by the model instead of code); medium; recorded as follow-up F15: scripting the statusline compose transform is a code change with its own tests, not an audit hunk.
  - F5 (`plugins/rate-limit-guard/reference/reader-contract.md:206-209`), Group 2, Volatile specifics (a harness-capability claim with no verification date); Group 2, Time-sensitive content ("until it stabilizes"); low; withheld; follow-up F6.
- **repo-fleet-hygiene** (3):
  - F13 (`plugins/repo-fleet-hygiene/skills/apply/SKILL.md:2 (frontmatter description)`), Group 2, Trigger-case enumeration (near-synonymous example queries); low; withheld, low confidence.
  - F14 (`plugins/repo-fleet-hygiene/skills/audit/SKILL.md:26 and :236`), Group 1c, Padding (near-duplicate sentences across sections); low; withheld; keep-list 10.
  - F15 (`plugins/repo-fleet-hygiene/skills/setup/SKILL.md:126-128 (setup delta)`), Group 1c, Padding (limits with escape hatches; commentary about the instruction); low; withheld, low confidence.
- **repo-hygiene** (1):
  - F9 (`plugins/repo-hygiene/skills/clean/reference/invocation-forms.md:14-16 (and its successor text after F1)`), Group 2, Volatile specifics (an API/harness capability claim with a source but no verification date); low; withheld; follow-up F6.
- **review** (6):
  - F16 (`plugins/review/agents/*.md:6 (all six agents)`), Group 4, Request config (an effort level pinned across a model change); low; withheld; effort sweep is a measurement item.
  - F17 (`plugins/review/agents/*.md:5 and plugins/review/skills/fanout/context/run-everything-mode.md:141`), Group 4, Request config (model routing with no recorded baseline); low; withheld; model routing without baseline.
  - F18 (`plugins/review/skills/quality-gate/context/pr.md:11-24, plugins/review/skills/quality-gate/context/code.md:7, plugins/review/skills/fanout/SKILL.md:127-129`), Group 2, Volatile specifics (harness capability claims with no verification date); low; withheld; follow-up F6.
  - F19 (`plugins/review/skills/security-review/SKILL.md:15-16`), Group 1d, Fossils ("known issue with [tool]" comment); Group 2, Volatile specifics; low; withheld; follow-up F6.
  - F20 (`plugins/review/skills/code-review/SKILL.md:47-50`), none (a sentence fragment; outside prompt-audit's pattern tables); low; withheld, low confidence.
  - F21 (`plugins/review/agents/ecosystem-specialist.md:22, plugins/review/skills/fanout/context/fix-pass-mode.md:7, plugins/review/skills/quality-gate/context/close-out.md:38, 102, 112, 260, plugins/review/skills/quality-gate/context/spec.md:59, 80, 104`), Group 2, Volatile specifics (hardcoded paths that resolve only in one repository); low; withheld; follow-up F8 (repo-relative citations that resolve only in the marketplace checkout).
- **session-flow** (11):
  - F26 (`skills/running-retro/SKILL.md:52-53 and skills/running-retro/context/checkpoint.md:136`), Group 1f, Output-shaping choreography (numeric ceiling); low; withheld, low confidence.
  - F27 (`skills/setup/SKILL.md:47-50 and skills/running-retro/SKILL.md:177, 210`), Group 2, Pinned model names; duplicated info across SKILL.md and the manifest; low; withheld, low confidence.
  - F28 (`skills/orient/SKILL.md:29-36`), Group 2, Volatile specifics (harness-behavior claims with no verification date); low; withheld; fleet follow-up F6 (verify and stamp undated harness claims).
  - F29 (`skills/keep-going/SKILL.md:166-169`), Group 2, Volatile specifics (undated harness claim); low; withheld; follow-up F6.
  - F30 (`skills/retro/SKILL.md:116-118`), Group 2, Volatile specifics (a setting default stated as bare fact, undated); low; withheld; follow-up F6.
  - F31 (`skills/handoff/context/gotchas.md:43-44 and skills/find-handoff/SKILL.md:213-215`), Group 2, Volatile specifics (undated harness-behavior claims); low; withheld; follow-up F6.
  - F32 (`skills/orchestrate/SKILL.md:40-41 and 99-101`), Group 1d, Fossils (a delegation-suppressing guardrail); low; withheld; candidate for the wave-1 behavioral spot-check on orchestrate.
  - F33 (`skills/orchestrate/context/sources.md:53-57, 74-76, 80-81, 263-267`), Group 2, Pinned model names (in citations backing a model-agnostic brief); low; withheld; refresh citations on the next sources re-verify.
  - F34 (skills/orient/SKILL.md:2, skills/find-handoff/SKILL.md:2, skills/reanchor/SKILL.md:2 (frontmatter `description`)), Group 2, Trigger-case enumeration (near-synonym lists); low; withheld, low confidence.
  - F35 (`skills/handoff/context/gotchas.md:37-38`), Group 2, The recency trap (one narrow conditional with a numeric threshold and no stated general principle); low; withheld, low confidence.
  - F36 (`skills/workflow/context/philosophy.md:16-18`), Group 1d, Fossils (a context-budget line written for context-limited sessions); low; withheld, low confidence.
- **setup-lane** (13); shared note: withheld; F20, F21, F22, F27 join follow-up F6; F23, F24 join a benchmark-figure note under F6:
  - T5 (`Undated harness-release claims`), Group 2, Volatile specifics (version numbers and API claims with no verification date); medium (pattern match); action withheld to `flag`; withheld; follow-up F6.
  - T6 (`"Do not invent an organization, repository, marketplace, or environment-variable prefix"`), Group 1c, Prohibition lists; signal `do not hallucinate` ("re-test whether you still need it - removal here is low confidence"); low; withheld, low confidence.
  - T8 (`Gotchas sections that restate rules already in the body`), Group 1c, Padding (repetition as reinforcement; near-duplicate sentences across sections); low; withheld; keep-list 10.
  - T9 (`Reconfiguration paragraph duplicated verbatim across the fleet`), none in prompt-audit's tables; keep-list 8 (working redundancy is not cruft); low; withheld; keep-list 8.
  - F12 (`plugins/source-control/skills/setup/SKILL.md:315`), Group 2, The recency trap (a standing invitation to encode each session's stumble as a permanent rule); medium; already covered by source-control F66.
  - F20 (`plugins/discovery/skills/setup/SKILL.md:57-62, :63-71, :85`), Group 2, Volatile specifics (harness version numbers stated as bare fact, no verification date, no recheck trigger); low; see the shared note.
  - F21 (`plugins/computer-use/skills/setup/SKILL.md:30 and :44`), Group 2, Volatile specifics (product-availability and plan-tier claims with no verification date); low; see the shared note.
  - F22 (`plugins/dometrain/skills/setup/SKILL.md:112-113 and plugins/miro/skills/setup/SKILL.md:102-103`), Group 2, Volatile specifics (a hardcoded harness path stated as fact, no verification date); low; see the shared note.
  - F23 (`plugins/context7/skills/setup/SKILL.md:91`), Group 2, Volatile specifics; a restated external benchmark figure with no recheck trigger; low; see the shared note.
  - F24 (`Measured figures in the statusline guard plugins`), Group 2, Volatile specifics; restated figures with no verification date or recheck trigger; low; see the shared note.
  - F25 (`plugins/actionlint/skills/setup/SKILL.md:100-106`), Group 2, Volatile specifics (a version-pinned claim); dated, but with no recheck trigger; low; see the shared note.
  - F26 (`plugins/ai-briefing/skills/setup/SKILL.md:99-100`), Group 2, Time-sensitive content ("current" with no date and no statement of what the restriction is); low; see the shared note.
  - F27 (`plugins/autonomy/skills/setup/SKILL.md:112-116 and templates/ci-otlp-artifact.md:94-97`), Group 2, Volatile specifics (API and beta-flag claims whose verification stamps carry no date and no recheck trigger); low; see the shared note.
- **skill-quality** (2):
  - F8 (`plugins/skill-quality/skills/check/SKILL.md:160-164 and :170-172`), Group 2, Volatile specifics (harness-capability claims with no verification date); low; withheld; follow-up F6.
  - F9 (`plugins/skill-quality/skills/setup/SKILL.md:16-20`), Group 2, Volatile specifics; low; withheld; setup lane T5 verdict stands; follow-up F6.
- **songwriting** (2):
  - F11 (`plugins/songwriting/skills/co-write/SKILL.md:166-167`), Group 1d, "Migration-relative phrasing", plus the time-relative "today"; low; withheld, low confidence.
  - F12 (`plugins/songwriting/skills/object-writing/SKILL.md:99-101`), Group 2, "Volatile specifics"; low; withheld; follow-up F6.
- **source-control** (10):
  - F72 (`skills/babysit-prs/reference/freshness.md:20-26,45,80-82`), Group 2, volatile specifics (external API behavior claims with no verification date or recheck trigger); medium; withheld; follow-up F6 (undated external and harness claims).
  - F73 (`skills/babysit-prs/reference/safety.md:386-429`), Group 2, volatile specifics (harness-capability claims with version pins and no as-of date; doc links present, no recheck trigger); medium; withheld; follow-up F6.
  - F74 (`skills/pull-request/reference/monitor.md:388-389`), Group 2, volatile specifics (a named third-party bot's login, signalling convention, and timing, undated); medium; withheld; follow-up F7 (Codex-specific reviewer shapes).
  - F75 (`skills/pull-request/reference/readiness.md:41,83-92,140,147-156`), Group 2, volatile specifics (same as F74; the Gate 5 command bakes a vendor login into a control gate); medium; withheld; follow-up F7.
  - F76 (`skills/babysit-prs/reference/loop.md:462-474`), Group 2, volatile specifics (undated harness-capability claims stated as bare fact); low; withheld; follow-up F6.
  - F77 (`skills/commit/SKILL.md:96-97,341-346; skills/commit/reference/exec-bit.md:8-11`), Group 1a, trait claims ("you tend to"); Group 2, history narratives ("the observed failure"); low; withheld, low confidence.
  - F78 (`skills/pull-request/reference/prep.md:29`), Group 4, request config and architecture (a delegation cap); low; withheld; delegation-cap candidate for a behavioral baseline, alongside session-flow F32.
  - F79 (`skills/babysit-prs/reference/stuck-checks.md:62-67,95-98`), Group 2, volatile specifics (marketplace-specific workflow and repository names in a plugin body); low; withheld, low confidence.
  - F80 (`skills/pull-request/templates/checklist.md:9`), keep-list item 8 exception (duplicates that disagree): `create.md` §2.4.1 pushes through `push-branch.sh`; low; withheld, low confidence.
  - F81 (`skills/babysit-loop/reference/promotion-evidence-resolution.md:9,28,35,44; skills/babysit-prs/reference/safety.md:722`), outside prompt-audit's tables; citation form; low; withheld; follow-up F8 (cross-plugin relative links).
- **tdd**: none.
- **testing** (7):
  - F5 (`plugins/testing/skills/diagnose/SKILL.md:12-27`), Group 2, "Verbose SKILL.md explaining things the model already knows"; medium; fleet decision: the gather block keeps its settled wording, including the "pipe is the bound" paragraph and the "rather than pre-compute lines" sentence.
  - F6 (`plugins/testing/skills/plan/SKILL.md:12-28`), Group 2, as F5; medium; same.
  - F7 (`plugins/testing/skills/run-e2e/SKILL.md:12-27`), Group 2, as F5; medium; same.
  - F8 (`plugins/testing/skills/write/SKILL.md:12-27`), Group 2, as F5; medium; same.
  - F25 (`plugins/testing/skills/diagnose/SKILL.md:68 (and diagnose/context/investigate.md:16, write/SKILL.md:74)`), Group 2, "Volatile specifics: ... version numbers, API claims with no verification date"; low; withheld; follow-up F6.
  - F26 (`plugins/testing/skills/run-e2e/context/e2e.md:12`), Group 2, "Volatile specifics": an undated version floor; low; withheld, low confidence.
  - F28 (`plugins/testing/skills/run-e2e/context/e2e-config.md:5, 14, 35-37 (and non-ui.md:3, 5)`), No prompt-audit row; low; withheld, low confidence.
- **toolchain** (6):
  - F13 (`plugins/toolchain/skills/lint/SKILL.md:35-37`), Group 2, Volatile specifics (measured figures with no basis, date, or recheck trigger); low; withheld, low confidence.
  - F14 (`plugins/toolchain/skills/check/context/dotnet.md:52`), Group 2, Volatile specifics; dated, but with no recheck trigger; low; withheld, low confidence.
  - F15 (`plugins/toolchain/skills/check/context/go.md:38`), Group 2, Volatile specifics (a verification stamp with a toolchain version but no date and no recheck trigger); low; withheld, low confidence.
  - F16 (`plugins/toolchain/skills/check/SKILL.md:24-27 and plugins/toolchain/skills/lint/SKILL.md:24-27`), Group 2, Volatile specifics (an undated harness-capability claim stated as bare fact); low; withheld; fleet template, follow-up F6 pool.
  - F17 (`plugins/toolchain/skills/check/SKILL.md:191-197 and plugins/toolchain/skills/lint/SKILL.md:214-224`), Group 1c, Padding (near-duplicate sentences across sections); low; withheld; keep-list 10.
  - F18 (`plugins/toolchain/skills/check/SKILL.md:2`), Group 2, Trigger-case enumeration ('run tests' and 'run the tests' are the same intent); low; withheld, low confidence.
- **verification** (3):
  - F6 (`plugins/verification/skills/measure/context/performance.md:65`), Group 2, Volatile specifics (a count about another marketplace's skill, stated as bare fact with no verification date or recheck trigger); medium; superseded by L1 below (the whole bullet goes).
  - F8 (`plugins/verification/skills/confirm/SKILL.md:55, :68-69, :75, :138, :145, :153 and plugins/verification/skills/measure/SKILL.md:63-68`), Group 1c, Padding (repetition as reinforcement; near-duplicate sentences across sections); low; withheld; keep-list 8 and 10.
  - F9 (`plugins/verification/skills/measure/SKILL.md:2`), Group 2, Trigger-case enumeration (nine quoted phrases; 'is it faster', 'did that actually speed it up'); low; withheld, low confidence.
- **visualization**: none.
- **wizard** (2):
  - F1 (`plugins/wizard/skills/generate/SKILL.md:99-104`), Group 1a, pressure language; low; withheld, low confidence; keep-list 3 (credential-handling gate carries its reason).
  - F2 (`plugins/wizard/skills/generate/SKILL.md:86`), Group 1c, padding row, matching the "near-duplicate sentences across sections"; low; withheld, low confidence; keep-list 8.
- **work-items** (7):
  - F17 (`The telemetry upsert is a 60-line shell block the model transcribes, in two files`), Group 4, An LLM executor for a deterministic plan (a fixed sequence whose inputs fully determine its output); medium; recorded as follow-up F11 in the record: extracting the 60-line upsert into `plugins/work-items/scripts/lane-telemetry-upsert.sh` is a mechanism change that needs its own script, test suite, and loop-lane convention review, not an audit hunk. Leave both fenced blocks and the classifier-fallback section as they are.
  - F18 (`Undated harness-behavior claims (6 sites)`), Group 2, Volatile specifics (harness and tool claims with no verification date or recheck trigger); low; withheld; follow-up F6.
  - F19 (`Gotchas that restate rules already in the body`), Group 1c, Padding (repetition as reinforcement; near-duplicate sentences across sections); low; withheld; keep-list 10.
  - F20 (`Purpose paragraphs that restate the description verbatim`), Group 1c, Padding (repetition as reinforcement); low; withheld; keep-list 8.
  - F21 (`Remaining near-duplicate trigger pairs`), Group 2, Trigger-case enumeration (the same row as F11, at a scale too small to call growth); low; withheld, low confidence.
  - F22 (`decompose/context/container-lifecycle.md:14, "Step 3 (above)"`), none in prompt-audit's tables; a stale relative pointer left behind when the section moved out of `SKILL.md` into a context file; low; withheld, low confidence.
  - F23 (`onboard-adapter/SKILL.md:5-8 and :12, YAML comments carrying maintainer rationale`), Group 2, History narratives (a justification for a frontmatter value, addressed to maintainers); low; withheld, low confidence.
- **x** (2):
  - F5 (`plugins/x/skills/read/SKILL.md:153-154, 226`), Group 2, "Volatile specifics"; medium; withheld; follow-up F6 (needs live egress to re-verify).
  - F6 (`plugins/x/skills/read/SKILL.md:160-192 and plugins/x/skills/read/context/failure-modes.md:30-92`), Group 2, "duplicated info across SKILL.md and reference files"; Group 1c, "repetition"; low; withheld; keep-list 8.

## Follow-ups

Inventoried here as they arise and shipped in the PR body verbatim.

- F1. Write one superseding ADR covering every accepted ADR decision this audit contradicted (at minimum ADR 0004 D-1 and D-3, ADR 0006's applied-set gate); decide with the operator whether ADR 0005 and ADR 0008 are also retired.
- F2. Audit the out-of-scope prompt surfaces the same way: hooks prompt text, output styles, `.claude/rules`, `CLAUDE.md`, `AGENTS.md`, and the plugin-level `reference/` trees that skills load on invocation (`autonomy`, `architecture`, `performance`, `playbooks`, `rate-limit-guard`, `context-guard`); the performance auditor notes that `snapshot` and `verify` both mandate reading `plugins/performance/reference/harness-integrity.md`, which likely mirrors the archaeology the skill bodies shed.
- F3. Behavior measurement beyond the wave-1 spot-check: route to `claude-config:unhobble`.
- F4. Graduate `docs/topics/prompt-audit-skills/PLAN.md` into this record and remove it before the PR (contract-slice prune gate).
- F5. `plugins/skill-quality/scripts/check-skill.sh` check 3 hard-fails any trigger phrase dropped versus the base ref. That blocks prompt-audit's documented fix for trigger-case enumeration (near-synonym lists become intent categories). Change check 3 to a warning, update its tests, and record the deliberately dropped phrases per skill in this record. Must land before the PR so the skill-quality CI gate passes. Landed in a694011bf; two out-of-scope surfaces still describe check 3 as a hard-FAIL gate and should follow: the comment at `plugins/docs-hygiene/skills/audit-noise/scripts/emit-findings.sh:220` and the eval fixture `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/negation-trigger-fence.md:9` (the docs-hygiene commit corrected the same script's header comment and its eval case 12).
- F6. Verify and stamp the undated harness-behavior claims the audit flagged as `I12` items (session-flow: `/recap` trigger and the Skill-invocable allowlist, the usage-limit reset surface, `cleanupPeriodDays` default, `/clear` transcript and scheduled-task behavior). Each becomes a four-part upstream-drift record or a doc pointer. Collected per plugin as the waves run. source-control adds: GitHub `mergeStateStatus` precedence and `baseRefOid` staleness (freshness.md), the permission-mode and wrapper-strip claims in safety.md, and the ScheduleWakeup clamp, `/loop` expiry, Monitor-on-resume, and sandboxed-GraphQL claims across babysit-prs, babysit-loop, pull-request, and worktree. disk-hygiene adds four undated harness-version claims (`safety-model.md:262`, `:313`, `:315` on 2.1.207 and 2.1.218 `pluginConfigs` scope and PowerShell hook firing; `clean/SKILL.md:382` on the v2.1.211 auto-mode prompt). performance adds the undated benchstat `-delta-test` claim at `snapshot/SKILL.md:94-96`, and `plugins/performance/reference/harness-integrity.md` (out of audit scope, mandated reading for `snapshot` and `verify`) likely carries the run archaeology the four skill bodies shed (see F2).
- F7. `pull-request` hardcodes one vendor's review bot (login, emoji signalling, timing) in `reference/monitor.md` gotchas and `reference/readiness.md` Gate 5, against the file's own "discover actors, don't hardcode them" rule. Parameterize Gate 5 on the discovered reviewer login and move the vendor shapes into a dated reference-shapes note with a recheck trigger.
- F8. `source-control` cites sibling-plugin files by relative path (`../../../../autonomy/...`, `../../../../../prompts/...`) in `babysit-loop/reference/promotion-evidence-resolution.md` and `babysit-prs/reference/safety.md`. Those resolve only in the marketplace checkout, never in an installed plugin. Convert to the raw-URL form the plugin already uses at `babysit-loop/SKILL.md:40`. review adds: `agents/ecosystem-specialist.md:22`, `fanout/context/fix-pass-mode.md:7`, `quality-gate/context/close-out.md` (four sites), and `quality-gate/context/spec.md` (three sites) cite marketplace `docs/` paths or sibling-plugin files by relative path. review also adds two undated claims to F6: the bundled `/code-review` and managed Code Review service tiers in `quality-gate/context/pr.md` and `code.md`, and the "built-in `/security-review` is unusable in CI" claim in `security-review/SKILL.md`.
- F9. `planning/skills/wayfind/SKILL.md` pre-compute silently coerces a non-string `container_label` to `work-map`, which `context/tracker-mechanics.md` says is a configuration error that must never proceed. Make the pre-compute fail loud or surface the raw value, matching the doc.
- F11. `work-items` carries the same 60-line lane-telemetry upsert as a fenced shell block in `work-loop/reference/telemetry-upsert.md` and `attend-queue/reference/telemetry-upsert.md`, transcribed by the model on every cycle, with a classifier-fallback section asking it to re-derive gate order by hand (prompt-audit Group 4, an LLM executor for a deterministic plan). Extract it into `plugins/work-items/scripts/lane-telemetry-upsert.sh` with a co-located test, taking lane, instance, repo, issue, and body-file arguments and exiting non-zero on each refusal branch; both references then invoke it. Deferred from the audit because it is a mechanism change, not a prose hunk. work-items also adds six undated harness and `gh` claims to F6 (classifier refusals of `permissions.allow` widening and of the `reclaim` call, the compound-shell block, sandboxed GraphQL 403).
- F12. `shell: bash` frontmatter selects the shell for `!`...`` injections. Skills whose pre-compute block became empty when the git lines moved into body calls still carry the key inert (debugging F5 found one). Sweep every SKILL.md: where no injection remains, drop the key; `check-skill.sh` check 19 stays green either way.
- F13. `playbooks:boris` presents Fable 5 as the current top model and its launch-era classifier behavior as current (`skills/boris/SKILL.md:58,133`); upstream has not published Fable 5.1 tips. Re-sync through `/playbooks:update` when it does, and until then qualify the Model row "as of the 2026-07-24 sync".
- F14. The `fable-5` playbook's own regeneration trigger ("a model-version change", `skills/update/SKILL.md:39`) has fired with Fable 5.1. The audit adds the guide-backed minimum, a `fable-5-1.md` adaptation chapter; regenerating the whole pack from Fable 5.1 is the maintainers' larger call. playbooks also adds to F8: `reference/model-adaptation/opus-5.md:207-208` cites a probe record (`thinking-off-probe-2026-07-26.md`) that exists nowhere in the repository. And to F6: the cache-pricing stamp at `skills/fable-5/context/orchestration.md:97` carries a date but no recheck trigger.
- F15. The statusline compose transform in `unwrap-before-compose.md` (synced between `context-guard` and `rate-limit-guard`) is a pure function of the effective `statusLine` string that the model hand-executes over roughly a hundred lines of prose, with eight eval cases checking the arithmetic (prompt-audit Group 4). Extract it into a synced `scripts/compose-statusline-wiring.sh` with the round-trip check inside, shrink the reference to the contract, and turn those eval cases into script tests. Deferred from the audit as a mechanism change. rate-limit-guard also adds to F6: the undated "Monitors is an experimental Claude Code component" claim in `reference/reader-contract.md:206-209`.
- F16. `claude-ops/skills/plugins/SKILL.md:268-276` records that its own probe's recheck trigger has fired (the CLI moved from 2.1.218 to 2.1.240 with the claim un-retested). Re-run the probe and refresh the stamp. claude-ops also adds nine undated harness and upstream-issue claims to F6 (bundled `doctor` gating, `audit-native-overlap` alias examples, `inventory` command aliases, the WebFetch truncation window, the `CLAUDE_PLUGIN_DATA` export claim, the `lanes` "verified on this machine" lines, the `observability` `session_id` and Stop-hook gotchas, upstream issue states in `read-routing.md` and `sync.md`, and the triggerless `surfaces.md` stamp) and two measured figures (`backups/` retention, the 97 percent and 50 MB figures in `observability`). `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh` fails 5 of 180 cases on this host (the worktree-root-unconfigured placement and header cases, the symlink discovery-root case, the intermediate-symlink case, and the unreadable discovery-root case); the scripts are untouched by the repo-fleet-hygiene commit and the finding-kind table assertion passes.
- F17. `context-guard/skills/setup/SKILL.md` runs four fixed read-only probes (jq presence, installed shim versus shipped source, session snapshot, `zones.json`) as model-issued Bash calls where a `## Pre-computed context` block would run them before the body loads (prompt-audit Group 4). Adding one is a mechanism change: the block must pass `scripts/check-skill-precompute-compose.sh` and stay inside the worktree guard's rule that a composed block expands nothing but bare `$HOME`, so it is deferred from the audit. context-guard also adds to F6: the undated `disableAllHooks` / `allowManagedHooksOnly` claims in `skills/setup/SKILL.md:93-96` and `reference/reader-contract.md:503-507`, the undated PowerShell routing note in `statusline-edit.md:106-109`, and the folklore-number paragraph at `reader-contract.md:383-391`, which is dated but has no recheck trigger.
- F18. `autonomy/reference/autonomous-pipeline-reminder.md` (out of audit scope; cited only by the README and a hook) rewords the vendor's autonomy block under the repo's no-copy rule and omits the Fable 5.1 clause "Do not stop because the context or session is long"; the guide calls the opening sentence load-bearing as written. Weigh the no-copy rule against that claim and add the missing clause in the plugin's own words. autonomy also adds to F6: the undated `AGENTS.md`-reachability claim stated three times (`skills/setup/SKILL.md:267`, `context/prerequisite-resolution-slice.md:38-39`, `reference/prerequisite-resolution.md:86-88`), the undated empirical telemetry claims in `reference/telemetry.md`, and the "shipped first-party mechanisms today" claims in `reference/runner/escalation.md:140-152`.
- F19. `plugin-quality/skills/audit/SKILL.md:58-92` has the model resolve the context zone by hand from inlined band tables, a staleness window, a version floor, and a combination rule that `plugins/context-guard/scripts/context-zone.sh` already implements (prompt-audit Group 1b and Group 4). Ship a byte-identical synced copy at `plugins/plugin-quality/scripts/context-zone.sh` with its test, register it in `scripts/cross-plugin-source-registry.txt` with a `sync-context-zone.sh --check` entry, and have the gate and `setup/SKILL.md:28-30` call it. Deferred from the audit as a mechanism change. plugin-quality also adds to F6: two live doc-page titles quoted undated in `agents/auditor.md:117-119`, the `context: fork` and cloud-scoping claims in `references/component-types/skill.md:18-24`, and six dated stamps with no recheck trigger. skill-quality adds to F6: three undated harness claims outside the dated stamp in `check/SKILL.md:160-172`, and the `setup/SKILL.md:16-20` stamp that has no recheck trigger. instruction-placement adds to F6: the undated "other agents resolve nearest-wins" claim in `realign/context/apply-recipes.md:95-97`. context-budget adds to F6: the `v2.1.232` measurement at `audit/SKILL.md:226-228`, the `/doctor` availability and `disableModelInvocation` claim at `audit/SKILL.md:34-36`, the cited-but-undated mechanism claims in `audit/reference/engine.md:25-30` with the dangling "verified version" referent at `:52-53`, and the wall-clock range at `audit/SKILL.md:93`. computer-use adds to F6: the dated surface table in `diagnose/SKILL.md:62-63` and the dated basis in `diagnose/reference/windows-quirks.md:5-6`, both without a recheck trigger. overengineering adds to F6: the undated harness-behavior claim in the gather blocks of all three skills (`audit/SKILL.md:20-23`, `delta/SKILL.md:19-23`, `realign/SKILL.md:19-22`, covered by the one dated record the worktree skill will own) and the undated `/loop` capability claims in `delta/context/recurring-wiring.md:37-38,51-53`. improvement adds to F6: four undated GitHub REST and Claude Code CLI claims in `find/context/ci-health.md:32-41`, `find/SKILL.md:235-237`, and `find/context/unattended.md:74-75`. docs-hygiene adds to F6: the bundled `/batch` skill claim in `extract-ssot/actions/batch.md:35,281`, four undated external benchmark figures across `extract-ssot/SKILL.md:27`, `context/anti-patterns.md:129`, and `context/decision-framework.md:27-59`, and the undated upstream-publishing claim in `audit-encapsulation/context/public-surface-contract.md:5`. code-tidying adds to F6: the CodeScene agentic-refactoring figure in `tidy/reference/scope-budget.md` "Research lineage" has no resolvable source; the audit dropped the number and kept the qualitative claim until a publication URL and read date are recorded. repo-hygiene adds to F6: the sourced-but-undated `${CLAUDE_SKILL_DIR}` substitution-scope claim in `clean/reference/invocation-forms.md`. disk-hygiene adds to F6: four undated harness-version claims across `clean/SKILL.md` and `clean/reference/safety-model.md` (report F15). codebase-health adds to F6: the undated harness-capability claim at `audit/SKILL.md:25-28`, verified true by the auditor on 2026-09-04 and needing only its dated record. architecture adds to F6: the undated pre-compute execution claim at `improve/SKILL.md:25-28`. mcp-tools adds to F6: three cited-but-undated Claude Code client-behavior values in `audit/reference/checklist.md:38,105,106`. performance adds to F6: the undated benchstat flag-set claim in `snapshot/SKILL.md:94-96`.
- F20. `provenance/skills/audit` spells one tier two ways: `not-found` in `SKILL.md:2,82,227` and `source-not-identified` in `reference/rubric.md:297`, and `scripts/emit-findings.sh` with its test asserts both. Pick one spelling, change the script and `emit-findings.test.sh` with it, and align the markdown in the same commit. Deferred from the audit because the fix crosses into a script and its suite.
- F21. `mutation-testing/skills/setup/SKILL.md:80-89` has the model re-derive a suppression entry's `finding_id` hash from its constituents and check node-kind membership by hand (prompt-audit Group 1b and Group 4, the same shape as F19). Ship `plugins/mutation-testing/scripts/suppression-lint.sh` with a test implementing the two published derivations and the membership check, have setup call it, and retarget setup eval 5 and audit eval 3 from "the model re-derives" to the script. Deferred from the audit as a mechanism change.
- F22. `plugins/ai-briefing/skills/setup/evals/evals.json:33` prompts `/ai-briefing:setup --with-build-deps`, but the skill's contract is `apply install-build-deps`; the case exercises a flag the skill does not accept. Retarget the prompt to the contract form. Observed by the ai-briefing auditor outside the audit's markdown scope.
- F23. `plugins/dometrain/skills/sync/context/update.md` documents the maintainer-only `--refresh-baseline` command through `${CLAUDE_PLUGIN_ROOT}`, which resolves to the installed plugin cache in a normal session, while the next paragraph forbids running it anywhere but a working clone; the script writes next to itself either way. Give the command as a clone-relative path, or document that the flag is only safe under `--plugin-dir`. A script-safety contradiction, not a prose hunk; observed by the dometrain auditor.
- F24. Add a criteria row to `plugins/claude-config/skills/audit-instructions/reference/criteria.md` for each recurring shape in [Catalog gaps](#catalog-gaps): dated stamps with no recheck trigger, migration-relative phrasing inside reference and context files, routing text that names a skill absent from `plugins/`, sibling-file meta-commentary, and maintainer rationale inside model-facing YAML comments; the rest are one-offs and stay listed.
- F10. Not an audit finding, recorded so it is not mistaken for one: `.claude/hooks/cloud-bootstrap-plugins.test.sh` fails 15 of 32 assertions on this Windows host ("not installed at user scope") with `.claude/cloud-bootstrap.sh` and the suite byte-identical to `origin/main`. The failure is environmental or pre-existing; confirm on CI and file separately if it reproduces there. Same status for `plugins/docs-hygiene/skills/audit-noise/scripts/emit-findings.test.sh` ("tier is looked up as IMPORTANT", "Location is repo-relative") and `plugins/provenance/skills/audit/scripts/list-corpus.test.sh` and `emit-findings.test.sh` ("a directory target lists its markdown"), which fail on this host with their scripts and suites byte-identical to `origin/main`. Same again for `plugins/work-items/skills/onboard-adapter/scripts/generate-adapter.test.sh` case 116, and for the nine eval-case digest assertions in `plugins/planning/tests/interview-defenses.test.sh` (`interview/evals/evals.json` unchanged since the digests were pinned; local jq 1.8.2), and for four Windows temp-path cases in `plugins/instruction-placement/scripts/verify-load.test.sh` (selected by a basename collision on `typescript.md`; the probe and suite are unchanged on this branch), and for `plugins/claude-ops/skills/audit-install-state/scripts/install_state.test.sh` (a Windows filename-syntax error on a fixture path) and `plugins/claude-ops/skills/audit-skill-visibility/scripts/audit_skill_visibility.test.sh` (no `installed_plugins.json` in the temp config), both with scripts and suites byte-identical to HEAD, and for `plugins/claude-ops/skills/plugins/scripts/fleet-state.test.sh`, which fails a varying subset of its 74 cases on this host (six inside a check-skill run, two when run alone) with the scripts byte-identical to `origin/main`. Same again for `plugins/claude-config/skills/audit-instructions/scripts/restatement-scan.test.sh` (two I29 fixture cases, script and fixtures byte-identical to `origin/main`) and the one `emit-findings.test.sh` case downstream of it ("Action names a body cut"), which reads the same scanner's output. Same again for `plugins/claude-config/skills/audit-permission-grants/scripts/permission-rule-check.test.sh` case 6b ("vendored copies excluded, exactly one finding"), whose script and suite no branch commit touched (main has since tidied the suite in ac7eeeac8). The fleet gather block itself ("the harness runs a skill's whole pre-compute block as one shell invocation") is an undated harness claim in about 55 skills; one dated four-part record on the worktree skill, which owns the mechanism, with the copies pointing at it, clears every site at once. discovery adds six undated claim families across thirteen files (silent preload failure, `AskUserQuestion` and plan-mode tools filtered from non-fork subagents, the Workflow tool absent from subagents, background as the default execution mode, spawns permission-classified before launch); the fix is one dated record per claim in the plugin's `reference/parent-contract.md` with the skills pointing at it. claude-config adds the undated `pre-v2.1.211` boundary at six body sites (the dated owner is `audit-permission-state/reference/criteria.md`), dated-but-triggerless stamps across eight files, the `conflict-scan.sh` precision figures in `conflict-criteria.md`, and the "Fable 5 subpage" pointers in `audit-prompting-postures/reference/postures.md` that need a Fable 5.1 sibling once it exists. discipline adds five files of undated fork-mode harness claims (`sweep-all/SKILL.md`, its two references, `scrutinize-dont-coast/SKILL.md`, `use-your-skills/SKILL.md`). claude-memory adds the undated upstream-issue state at `audit/reference/official-guidance.md:168`. testing adds the xUnit v3 and .NET 10 framework-trap claims (`diagnose/SKILL.md:68`, `diagnose/context/investigate.md:16`, `write/SKILL.md:74`) and the `playwright-cli` version floor in `run-e2e/context/e2e.md:12`. planning also adds two undated harness claims to F6: the agent-teams "experimental, default-off" status in `plan/SKILL.md` and the "cannot read effort or advisor state" claim in `interview/context/session-config.md`. `plugins/ai-slop/skills/audit/scripts/detect.test.sh` fails its four "git absent" cases (4 of 202) on this Windows host because the test symlinks the shell builtin `printf` into a fake PATH directory (`ln: failed to create symbolic link`); the scripts are unchanged by the ai-slop commit. `plugins/disk-hygiene/skills/clean/scripts/guard_launch_monitor.test.sh` fails its two telemetry-sink cases and `hygiene.test.sh` fails `test_stash_must_exist_in_an_independent_checkout` and `test_preview_allows_root_children_os_managed_snapshot` on this host with the scripts byte-identical to HEAD; neither case reads markdown, and the frontmatter-belt assertions in `test_hygiene.py` that do read `clean/SKILL.md` pass after the disk-hygiene commit. `plugins/code-tidying/skills/audit-comment-residue/scripts/detect.test.sh` fails 4 of 53 cases on this host (embedded quote and backslash unescaping in the preview script, arrow-in-filename, tab-bearing path) with `detect.sh` and the suite byte-identical to HEAD; the code-tidying commit touches only prose the script does not read. `plugins/knowledge/skills/docpage-digest/scripts/check-fences-exact.test.sh` fails six cases on this host with a `UnicodeEncodeError` writing U+2265 to the cp1252 console, script and suite byte-identical to HEAD; the knowledge commit touches no fence, quote payload, or script. `plugins/education/skills/teach/scripts/list-workspaces.test.sh` fails "worktree lists the MAIN repo's workspace" on this worktree checkout with the script unchanged.
