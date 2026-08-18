# skills-discovery-plugin

## Brief

### TLDR

A read-only `claude-ops` skill that answers **"why am I not using most of my skills?"** — and
answers it with the mechanism, not a tally. Claude Code budgets the skill listing at ~1% of the
context window and, on overflow, **drops descriptions starting with the skills you invoke least**.
A skill at zero usage loses its description, loses the keywords the model matches against, and
stays at zero. The skill's job is to separate **starved** (suppressed by that loop, still wanted)
from **genuinely unwanted** (safe to disable) from **not observable** (no data — never a verdict).

This is deliberately *not* a usage heat map. Claude Code already ships unused-skill reporting
(`/doctor` Check 1; `/skill-doctor`, whose function moved into a Stats tab). Rebuilding that is
disfavored by `/discipline:reuse-or-replace`. The differentiated remainder is the starvation
diagnostic, `invocation_trigger` attribution, per-repo/trend detail, and the why-classification.

### Goal

Ship `/claude-ops:audit-skill-starvation` — a read-only findings report that, for the operator's
own machine, classifies every enabled skill into a reach state, explains each cold verdict against
documented Claude Code mechanics, and withholds verdicts entirely when the data cannot support them.

### Constraints

**Data sources — ladder, never summed.**

1. **`claude_code.skill_activated`** (OTEL, documented, first-party) — the preferred source. Carries
   `skill.name`, `skill.source`, and `invocation_trigger` (`user-slash` | `claude-proactive` |
   `nested-skill`). `invocation_trigger` is the only source that separates *"Claude never picks
   this"* from *"I never run this"*, and it closes the nested-skill attribution gap. Requires a
   collector; `skill.name` is redacted to `custom_skill` for third-party skills unless
   `OTEL_LOG_TOOL_DETAILS=1`, which also widens collection to tool arguments and error strings —
   surface that privacy cost, never enable it silently.
2. **`skill-usage.jsonl`** (this plugin's hooks) — the no-collector fallback. Adds branch/project
   and the tool-vs-expansion split. Scope-resolved via `claude_ops::resolve_skill_usage_dir`.
3. **`~/.claude.json` `skillUsage`** — lifetime-since-install baseline ONLY. Undocumented, no
   stability guarantee, absent from all 22 doc pages and the 521 KB changelog. Read defensively;
   check the qualified key AND the bare-name fallback.
4. **Session transcripts** `~/.claude/projects/<sanitized-cwd>/*.jsonl` — optional; the only
   retroactive signal and the only source enumerating every project the operator has opened.

- **NEVER sum sources.** Native and JSONL were demonstrated live to record the same invocation with
  matching sub-second timestamps; over the JSONL window native is a strict duplicate, not a
  complement. Reconcile by `max()` per skill, or use native for lifetime count and JSONL for
  attribution only.
- **`pluginUsage` is BANNED as a skill signal.** It counts hook/agent/MCP/LSP dispatch, not skill
  invocation (measured: `guardrails` 105, `context-guard` 98, `claude-ops` 90, all with zero skill
  invocations). It is seeded at install with `usageCount: 0` and a current `lastUsedAt` — 46 of 65
  plugins would read as "used today" when none had been used. Permitted use: install-seed detection
  only, gated on `usageCount > 0`.
- **Native counter mechanics that change the arithmetic:** a 60-second per-skill write debounce
  (bursts undercount) and lifetime-only counts (can never answer "used in the last 30 days").

**Denominator.** Installed **and enabled** — checkout, installation, and enablement are three
different sets by `claude-ops:inventory`'s own doctrine, and skills in installed-but-disabled
plugins must not be libeled. Prefer `claude_code.plugin_loaded`; otherwise inventory plus an
enablement check. Call `skills/inventory/scripts/inventory.py --out` for the fleet — never
re-enumerate it. The join is not free: usage keys are `<plugin>:<leaf>`, while inventory emits bare
leaf names nested under `disk.installed_plugins[<marketplace>][<plugin>].components.skills[]`, so
the qualified name must be synthesized from the enclosing dict keys. Two marketplaces shipping a
same-named plugin collapse to one usage key — detect and report the ambiguity rather than
misattributing.

**Classification.** Ground every cold verdict in the 13 documented never-auto-invoked reasons.
Three of those are silent misconfigurations and must NEVER be rendered as "delete me". Derivable
buckets: `disable-model-invocation: true` (59 of 213 local skills — 28% of the fleet),
`skillOverrides: "off"`, plugin-not-enabled, invoked-only-by-another-skill, and starved-by-budget.
Two candidate buckets are excluded as underivable: "described-but-never-triggered" (nothing records
"considered and not selected"; it is the arithmetic residual of the others) and
"used-elsewhere-but-not-here" (unreachable without cross-repo data in V1).

**Honesty floor — the load-bearing constraint.** Compute and print `observed_horizon` =
`now − min(firstStartTime, earliest event)`. Clamp every tier to it; refuse any window wider than
it. Add a **`not observable`** tier so "never invoked" and "never observed" can never collapse.
Below an exposure floor (LaunchDarkly's shape: 30 days since created, 7 days inactive), withhold
the verdict rather than guess. Measured motivation: on a 3-day-old install with a 1-day-old store,
90/30-day tiers put 210 of 213 skills in `never` and leave two tiers unreachable.

**Presentation.** Rank-actionable, not full-fleet. Group-adjacency (JetBrains Productivity Guide) to
surface the long tail; grouping keys are free (`plugin.name`, `skill.source`). No single "adoption
%" headline — coverage-style scores are useful for finding gaps and useless as a score.

**Repo conventions.** Skill name is an imperative verb phrase; `audit` is the fixed verb for a
read-only findings report (siblings: `audit-install-state`, `audit-performance`). Run
`scripts/check-skill-leaf-names.sh` on the new leaf. A standalone plugin is positively barred —
`docs/PLUGIN-PHILOSOPHY.md`: "It never imports files from a sibling plugin… A bare unguarded
cross-plugin reference is a defect" — and this skill must read `claude-ops`' store and script.
JSON output follows `docs/conventions/plugin-data-report-keying/README.md` Rule 1
(`${CLAUDE_PLUGIN_DATA}/<component>/<repo-identity>/<worktree-discriminator>/<filename>`), adopting
`lib/state-key.sh`; do NOT copy observability's `reports/claude-observability-<date>.md`, which
lacks the state key and is absent from that convention's adoption table. `claude-ops` has no `lib/`
yet, so adding it is part of this work.

**Ownership split (explicit, because both skills touch `.claude/observability/`).** The new skill
owns *interpretation* of skill-usage data. `observability` keeps hook-events, OTEL infrastructure,
and the single retention harness. `read-routing.md` gains a row pointing skill-reach questions here.

**A `userConfig` option cannot reach a skill's Bash script** — proven by
`docs/extensibility-contract-smoke-tests.md` Test B (`CLAUDE_PLUGIN_OPTION_*` is absent from a
skill-spawned subprocess's environment). A configurable window must arrive via
`${user_config.KEY}` substitution into SKILL.md or a flag the model passes.

### Acceptance criteria

1. `/claude-ops:audit-skill-starvation` runs read-only and never writes user-visible state except
   its keyed report artifacts.
2. Every skill in the enabled denominator resolves to exactly one reach state, including
   `not observable`.
3. The report prints `observed_horizon` and no tier boundary exceeds it.
4. With data below the exposure floor, the report withholds cold verdicts and says why, instead of
   emitting a fleet-wide "never used" wall.
5. No output path sums two sources; the reconciliation rule is stated in the report.
6. `pluginUsage` is never presented as skill usage anywhere in the output.
7. Starved-vs-unwanted is computed and rendered, with the budget mechanism explained.
8. Silent-misconfiguration classes are rendered as fixable, never as removal candidates.
9. Markdown is the durable record; HTML is optional; JSON conforms to the keying convention
   (one file per run plus an appended history line — never a rolling `latest.json`).
10. `clean.sh` prunes `skill-usage.jsonl` across all three scopes via the hooks' path policy, under
    its own retention flag, with all four retention-doc locations updated together.
11. Churn uses `git log --follow` for counts and `git log -1 --format=%cI` for authoring date
    (filesystem mtime is checkout time — verified drift: 2026-08-15 clone vs 2026-08-12 commit).
12. The churn × usage cross-tab is labeled so it cannot read as "wasted authoring effort" — invalid
    for skills authored for consumers in a public marketplace.

### Captured assumptions

- Single-operator, local-machine scope. The shipped `skill_usage_git_exclude` option already
  contemplates a team that commits telemetry; this work neither removes nor builds on it.
- Cloud/ephemeral containers lose both stores with the container. Documented as a known gap; the
  honesty floor is what keeps that gap from becoming a false report.
- The 7-day half-life in the decay scorer is inferred from binary inspection, not documented — do
  not present the starvation cutoff as exact without re-verification.
- No official Anthropic position exists on third-party skill analytics: issue #35319 ("Skill
  invocation tracking and usage analytics") is closed with no maintainer response, and its
  predecessor #20970 was auto-closed for inactivity. Neither blessed nor blocked.

### Out-of-scope (V1)

- Any proactive in-session nudge hook. The always-on hook budget already "exceeds the ceiling
  several times over", and the binary exposes no skill-specific hook event beyond `PostToolUse` and
  `UserPromptExpansion` — so there is nothing new to hook, and no existing hook changes.
- Scheduled routines. Manual invocation only until coverage is trustworthy.
- Team/multi-operator aggregation and any committed usage store.
- Cross-repo aggregation as a headline promise. Unreachable under the shipped `repo` default scope;
  available only via user scope or transcripts, and reported as scope-limited when absent.
- Re-implementing fleet enumeration, and any dedupe pass (the hook writes one destination per
  invocation, so no event lands twice; id-less second-granularity rows mean a dedupe key would
  silently collapse genuine same-second invocations).

### Deferred questions

- **Q16 — Does the collector dependency ship as required or optional?** OTEL is strictly the best
  source but needs a running collector plus `OTEL_LOG_TOOL_DETAILS=1` for un-redacted third-party
  skill names. Arbiter: `/planning:plan`.
- **Q17 — Should the starvation cutoff be computed exactly** (reading the effective listing budget
  and ranking by the decay score) **or approximated** with a documented caveat? Depends on Q16 and
  on re-verifying the inferred half-life. Arbiter: `/planning:plan`.
- **Q18 — Adopt session transcripts in V1 or defer?** They are the only retroactive and only
  cross-repo-enumerable source, and the shipped Doctor uses them — but scanning ~50 recent files
  per project is the largest single cost in the design. Arbiter: **USER-RESERVED** — it changes the
  scope-limited framing the Brief currently commits to.
- **Q19 — Final leaf name.** `audit-skill-starvation` is proposed and satisfies both naming
  challenges (verb phrase; no consumer-adoption promise). Confirm against
  `scripts/check-skill-leaf-names.sh`. Arbiter: `/planning:plan`.

## Plan

*Not yet written — `/planning:plan` fills this section.*
