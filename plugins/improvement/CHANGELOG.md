# Changelog

All notable changes to the `improvement` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.2]

### Changed

- **`find`: the pipeline hand-offs name the Skill tool (#3002).** The interview-on-the-pick step,
  the explore/research/plan hand-off, and the execution-request pipeline sentence now say the
  named skills are invoked via the Skill tool. The remainder-filing line keeps its
  recommend-to-the-human shape ("the user decides which, if any") and only regains the leading
  slash its siblings all carry: `work-items:track` → `/work-items:track`. Wording only — this
  skill still performs no code edits in any mode, and the presence gates are unchanged.

## [0.1.1]

### Fixed

- **README opener said "One skill" for a two-skill plugin.** `/improvement:setup` shipped alongside
  `find` in 0.1.0 and appears in the table, but the sentence introducing it was never recounted — so
  the plugin's very first release described itself as smaller than it was. Found by
  `scripts/check-skill-count-claims.sh`, a new fleet gate that compares every hand-written skill
  count against the tree.

## [0.1.0]

### Added

- **Initial release** of the `improvement` concern: an evidence-first, cross-dimension
  improvement finder answering "what should we improve here, and how do we know?".
- **`/improvement:find` skill.** Ranked, evidence-cited candidate list across code/architecture,
  performance, product behavior, external config/automation, and Claude Code operational setup;
  evidence ladder with instrument-first rule and recorded evidence gaps; tiered, presence-gated
  evidence sources (Tier 0 repo-native, Tier 1 `claude-ops:observability`, Tier 2 configured MCP
  telemetry); interactive pick-interview-handoff flow feeding the planning pipeline;
  caller-declared unattended mode (persisted report, presence-gated deduped work-item filing
  under an adaptive prompt-overridable cap); explicit boundaries against `architecture:improve`,
  `code-tidying:tidy`, `codebase-health:audit`, `review:fanout`, and `work-items:scan-todos`.
- **Evidence recipes** as `context/` leaves: `hotspots.md` (plain-git churn×complexity with
  history-depth gate and cascade-overridable exclusions), `ci-health.md` (Actions run-window
  failure/duration/retry analysis with access-path probe ladder), `ranking.md` (WSJF-style
  scoring, evidence-rung confidence mapping, instrument-first), `unattended.md` (declaration
  contract, `${CLAUDE_PLUGIN_DATA}` report keying, filing flow, dismissed-candidate memory).
- **`/improvement:setup` skill.** Fleet-standard `check` (default, read-only) / `apply` actions
  over the `.claude/improvement.md` config cascade — verifies layer presence and
  tracked/ignored state, reports the effective evidence-source configuration with per-layer
  provenance, and interviews before writing the team file.
- **Config contract at `reference/config.md`** — the single home for the config keys: Tier 2
  `evidence_sources` MCP declarations, churn window and exclusion patterns, and the three-layer
  cascade resolution order (`~/.claude/improvement.md` → `.claude/improvement.md` →
  `.claude/improvement.local.md`) with declared merge semantics.
- **Evals** for both skills: trigger recognition for a vague prompt, a targeted prompt, and an
  unattended declaration (`find`); read-only check, interview-before-write, and
  tracked-config verification (`setup`).
- **README routine guidance.** Weekly Routine prompt template (the prompt as tuning surface)
  opening with the fired-environment guard, the cloud-session plugin-availability prerequisite,
  a GitHub Actions cron alternative via `claude-code-action@v1` with the `plugins:` input, and
  the note that `/loop` is session-scoped only.
