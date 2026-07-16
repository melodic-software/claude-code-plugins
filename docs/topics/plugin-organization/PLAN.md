# plugin-organization

## Brief

### TLDR

Reorganize the marketplace: adopt the `domain-noun:action-verb` naming grammar, execute the
plugin splits/merges/renames locked in the 2026-07-15 interview, keep the disk layout flat,
and normalize category metadata. Buckets are catalog metadata only — never namespaces, never
folders.

### Goal

Every skill invocation in the catalog is semantically accurate and stutter-free under the
grammar; plugin boundaries follow design (change-together, useful-alone), not migration
history; grouping lives in marketplace metadata.

### Locked decisions

| # | Decision |
|---|---|
| D1 | Disk layout stays flat `plugins/<name>`. Grouping = category metadata + catalog docs. |
| D2 | Naming grammar: namespace = noun (gerund for activity domains, plain noun for subject domains), skill = action verb (noun-phrase for knowledge skills). No stutter. Root-echo exempt (`implementation:implement`, `code-tidying:tidy`, `work-items:work`). |
| D3 | `diagnose` → `debugging` (skill `diagnose` unchanged). |
| D4 | `improve-architecture` → `architecture`, skill → `improve`. |
| D5 | `teach` → `education`, skill `teach` unchanged. |
| D6 | `review-toolkit` → `review`; skill `code-review-fanout` → `fanout`; `quality-gate` unchanged. |
| D7 | `boris` + `thariq-skills` + `fable-5-playbook` → new `playbooks` plugin, v0.1.0; skills `boris`, `thariq`, `fable-5` + central `update` (per-pack scripts stay inside each skill dir; fable-5 reports "self-authored, no upstream", regeneration trigger = model-version change). |
| D8 | `claude-config-audit` → `claude-config`; skills: `settings-audit` → `audit`, `automation-deep-dive` → `automation-gaps`, `permission-hygiene` unchanged; `memory-health` moves out. |
| D9 | New `claude-memory` plugin; skill `health` (was claude-config-audit's `memory-health`). |
| D10 | `claude-ops` unchanged as plugin; skills deprefixed: `claude-code-changelog` → `changelog`, `claude-observability` → `observability`, `claude-troubleshooting` → `troubleshoot`. |
| D11 | `mcp-tool-audit` → `mcp-tools`, skill → `audit` (verified generic-MCP, standalone domain). |
| D12 | `codebase-audit` → `codebase-health`, skill → `audit`. |
| D13 | `implementation` splits four ways: `toolchain` (`build`, `lint`, `setup`), `testing` (`plan`, `write`, `e2e`, `diagnose` — was test-*), `verification` (`confirm` — was verify-changes, `measure` — was verify-improvement), `implementation` (`implement`, `implement-dispatch`). Mechanism moves, obligation stays: implement builds via `/toolchain:build` seam; cross-plugin references presence-gated. |
| D14 | `tdd` stays standalone; skill → `principles`. |
| D15 | `work-items` skill splits five ways: `track` (add/start/done/list/stats/search/due/recheck/audit), `triage`, `work`, `decompose`, `scan`. |
| D16 | `context7`: skill → `lookup` + new `setup` (absorbs configure, `disable-model-invocation: true`); `update` stays inline maintainer action. |
| D17 | Skill renames: `machine-health` → `check`, `skill-quality` → `check`, `bug-report` → `write`, `ai-briefing` → `generate`, docs-hygiene `encapsulation-audit` → `audit-encapsulation`. |
| D18 | `playwright` skill → `test` (vendor-CLI verb convention). |
| D19 | Unchanged with grounds: guardrails whole (per-guard `HOOK_<NAME>_ENABLED` toggles exist), firecrawl one skill, `youtube` stays in knowledge, all shadow-dodge names kept on merit, hook-only formatter plugins stay separate, `event-storming`/`prototype`/`session-flow`/`miro`/`repo-hygiene`/`knowledge`/`discovery`/`planning`/`source-control`/`songwriting`/`docs-hygiene`(rest) unchanged. |
| D20 | Base-concept-first naming for skill families; natural order for standalone names. |
| D21 | Every upstream-sourced plugin carries an update/drift-check path. |
| D22 | Category vocabulary (15, noun/gerund form): discovery, design, development, testing, verification, quality, maintenance, deployment(deferred), claude-code, security, workflow, project-management, operations, learning, music, personal. Lifecycle-primary + subject catch-all; activity/subject tiebreak (subject wins when it's the salient trait). Assignments: discovery{discovery,context7,firecrawl,knowledge}; design{planning,architecture,prototype,event-storming,miro}; development{implementation,toolchain,source-control,markdown-formatter,bash-lint,biome-format,ruff-format,powershell-format,actionlint,eol-normalizer}; testing{testing,playwright,tdd}; verification{verification}; quality{review,codebase-health,mcp-tools}; maintenance{debugging,bug-report,code-tidying,repo-hygiene,docs-hygiene}; claude-code{claude-config,claude-memory,claude-ops,desktop-notification,playbooks,skill-quality}; security{guardrails}; workflow{session-flow}; project-management{work-items}; operations{machine-health}; learning{education}; music{songwriting}; personal{kindle-dedrm,ai-briefing}. `category` normalized to these; fine-grained old values migrate to `tags`. |
| D23 | Catalog presentation: grouped README section **generated** from marketplace.json (category+order) + plugin.json (description), between markers, **CI-enforced in-sync**. Retires the existing hand-maintained flat catalog + its description duplication. Build-tooling sub-task (generator + CI gate). |
| D24 | Category vocabulary defined in one owner doc **`docs/CATALOG-TAXONOMY.md`** (15 categories + glosses, noun-form rule, lifecycle-primary/subject principle, singleton governance, category-level triggers, generation contract). marketplace.json conforms; consumers cite, never restate. Plugin-specific deferrals stay in their plugin docs. |

### Constraints

- `renames` map entries are append-only; add one per plugin rename/merge (many-to-one verified
  legal on CC 2.1.210). Automatic migration requires CC ≥ 2.1.193.
- Each new/merged plugin clears the migration gate + plugin-acceptance security review
  (MIGRATION-PLAYBOOK).
- Skill renames must preserve description trigger phrases; sweep every cross-reference
  (`/docs-hygiene:rename-references`) — SKILL.md cross-refs, README, marketplace.json, hooks,
  agents, evals.
- Fresh-docs mandate applies at execution time (re-fetch plugin docs before edits).
- No commits without explicit approval; work lands as reviewable changes.

### Acceptance criteria

- `claude plugin validate .` passes; renames-map chains terminate.
- No invocation in the catalog violates the grammar (stutter list empty except root-echo exemptions).
- Plugin contract tests pass (`scripts/run-plugin-tests.sh`); CI green.
- Every moved/renamed skill reachable at its new invocation; old plugin names migrate via renames map.
- All doctrine codified in repo convention docs (see D-doctrine agent task).

### Captured assumptions

- Private single-owner marketplace: rename cost = own installs + own muscle memory.
- Version resets to 0.1.0 acceptable for new plugin identities (playbooks; split plugins).

### Out-of-scope (deferred with triggers)

- firecrawl `parse` extraction — trigger: local-file-extraction discovery failures, or non-credit backend.
- `youtube` standalone plugin — trigger: video-digestion becomes distributable package, or video-without-knowledge consumer.
- kindle-dedrm relocation — trigger: marketplace audience widens beyond owner (legal/compliance posture).
- work-items further decomposition of `track` — trigger: track's description approaches truncation or lanes diverge.
- Empty `deployment` category — created when first deploy plugin lands.
- `music` → `creative` rename — trigger: a non-music creative plugin lands.
- fable-5 regeneration — trigger: model-version change (self-authored, no upstream).

### Deferred questions

- Empirical check: typeahead prefix filtering on plugin-skill leaf names — `/architect`.
- session-flow category label `workflow` — judgment call (no marketplace precedent); revisit if a stronger authoritative label emerges.

## Plan

(unfilled — /architect)
