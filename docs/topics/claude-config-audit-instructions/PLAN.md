# claude-config-audit-instructions

## Brief

### TLDR

- New skill `/claude-config:audit-instructions` (issue #800): read-only audit sweeping the
  locally-owned Claude Code instruction surfaces — user + project CLAUDE.md, skill bodies +
  context files, agent definitions, `.claude/rules/**/*.md`, prompt-type hooks, output styles —
  proposing removals/rewrites of instructions current models no longer need.
- Check catalog seeded from the 11 sourced seeds in knowledge-corpus
  `.work/youtube-watch/how-i-plan-build-and-run-loops-with-clau-aVO6E181cNU/research/findings/context-trimming.md`,
  each check cited to its official source.
- Findings tiered by evidence class: **mechanical** (pattern-detectable: bare prohibitions
  without rationale, inferable/redundant content, misplaced only-sometimes-relevant content,
  rule-to-hook candidates, show-your-thinking instructions, non-steering example blocks) vs
  **behavioral** (pruning-bar counterfactuals — "would removing this cause mistakes?" — whose
  ground truth is observed behavior, not static analysis).
- Execution shape: per-surface subagent lanes sharing one check catalog; large lanes (skills)
  fan out further. Every removal proposal passes an adversarial "would removing this cause
  mistakes?" verify pass before reaching the human-gated diff.
- Output: findings report + proposed diffs, human-gated, never auto-applied. Upstream-owned
  findings route out (standards-managed materializations → melodic-software/standards per
  sync-manifest; marketplace plugin content → claude-code-plugins issues), never edited in place.

### Goal

A claude-config audit-family skill that, on demand or after a model-generation upgrade, tells the
operator exactly which instruction lines across their locally-owned Claude Code configuration are
no longer earning their context cost — with each finding cited to current official prompting
doctrine, classified by how confident the evidence can be, and packaged as a proposed diff the
human approves or rejects — so instruction surfaces shrink as models improve instead of accreting
prior-model-era scar tissue.

### Constraints

- Name locked: `audit-instructions` (this session, via naming pipeline). Family grammar:
  `audit` = read-only findings report; mutation never on bare invocation
  (`docs/PLUGIN-PHILOSOPHY.md` naming table).
- Human-gated output only: findings report + proposed diffs; never auto-applies. No `--fix`
  in scope for this issue.
- Scope bound (locked in issue #800 follow-up): audit only locally-owned surfaces (user
  CLAUDE.md, `~/.claude/rules`, project `.claude/`). Marketplace plugin cache content is
  upstream-owned — findings there route to claude-code-plugins issues, never local cache edits.
- Cross-repo routing: findings inside standards-managed materializations route upstream to
  melodic-software/standards per `standards/distribution/sync-manifest.yml` ownership.
- Composes by pointer, distinct intents (locked): `skill-quality:check` (structural lint),
  `docs-hygiene:compress` (token brevity), `claude-config:audit` (config-file mechanics —
  settings.json, .mcp.json, hooks wiring). This skill owns instruction *content* vs current
  model capability; no overlap restated.
- Check catalog is cited doctrine, not copied prose: each check carries its source URL
  (code.claude.com best-practices, platform.claude.com Fable 5 + prompting best-practices pages)
  with verified date and a recheck trigger — model-specific pages get superseded per release.
- Repo obligations: plugin version bump + CHANGELOG entry, skill-quality:check pass,
  validate-plugin-contracts gate, commit via `git commit -F - --cleanup=verbatim`.

### Acceptance criteria

1. `plugins/claude-config/skills/audit-instructions/` ships; frontmatter description carries the
   discovery triggers (post-model-upgrade, "prune my CLAUDE.md", "are my instructions holding
   the model back") and the distinguishing object in its first clause.
2. Check catalog covers all 11 seeds from the knowledge-corpus findings file; every check cites
   its official source.
3. Findings report tiers every finding mechanical vs behavioral; every removal/rewrite proposal
   carries the adversarial verify verdict before it is surfaced.
4. Bare invocation is read-only end-to-end; diffs are proposed artifacts, never applied.
5. Scope guard enforced in skill flow: plugin-cache and standards-managed paths are excluded
   from the editable set and their findings emitted as routing recommendations instead.
6. Per-surface lane execution shape (subagent per surface, shared catalog, fan-out for skills)
   is the documented default flow.
7. skill-quality:check passes for the new skill; claude-config version bumped with CHANGELOG
   entry; PR closes #800.

### Captured assumptions

- The 11-seed catalog reflects official doctrine as of 2026-07-21, re-verified against live
  docs this session (research pass) — revisit on next frontier model release or when either
  prompting page changes (recheck trigger recorded in the skill's sources).
- Attribution (research-verified 2026-07-21): the pruning bar "Would removing this cause
  Claude to make mistakes?" and the delete-and-watch loop ("test changes by observing whether
  Claude's behavior actually shifts") are Anthropic best-practices doctrine. Boris Cherny's
  documented practice is the additive write-it-down loop plus `/checkup` (dedup, split big
  CLAUDE.md into nested files + skills); a periodic full-delete ritual is unconfirmed in any
  primary source — the skill must not cite it as his.
- Bare-prohibition remediation (research-verified): the docs' primary target form is positive
  reframing ("tell Claude what to do instead of what not to do"); adding rationale is
  separately supported ("give the reason, not only the request"). The check offers positive
  rewrite first, prohibition-plus-rationale as the fallback where a genuine hard "never"
  survives.
- Examples remain officially recommended (3–5, format/tone/structure steering) for all current
  models including Fable-class — the audit flags example blocks only when they are behavioral
  scaffolding pinning the model's approach, never format steering; revisit if the
  best-practices page drops the recommendation.
- Behavioral-tier caution is itself sourced: Anthropic's postmortem on the ~80% system-prompt
  cut (InfoQ/VentureBeat coverage) records that narrow evals missed a ~3% regression —
  grounding why behavioral findings ship as proposals with the delete-and-watch loop, never
  as confident removals.

### Out-of-scope

- #798 (`library_dir` indirection) — separate item, not folded in.
- Any auto-apply / autofix mode.
- Building an eval harness for instruction A/B testing (the report may *recommend* the
  empirical loop; shipping tooling for it is not this issue).
- Auditing upstream plugin content in place (routing-only, per scope bound).

### Deferred questions

- Empirical validation posture: does the findings report prescribe the delete-and-watch +
  re-add-on-mistake loop (and cheap A/B for example blocks) as its recommended follow-through,
  or stop at the human-gated diff? — defer until /planning:plan; **arbiter: USER-RESERVED**
  (changes report shape and acceptance criterion 3's follow-through).
- Upgrade-trigger mechanics: how "upgrade-triggered" fires (manual invocation documented as the
  trigger vs any automation/hook seam) — defer until /planning:plan; **arbiter: /architect**
  (issue text already sanctions "upgrade-triggered or on-demand"; execution-shape decision).

## Plan
<empty — populated by /planning:plan>
