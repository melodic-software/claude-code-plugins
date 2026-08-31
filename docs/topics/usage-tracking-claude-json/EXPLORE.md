# Usage tracking: what `~/.claude.json` records, and what this repo already builds on it

Exploration only. No component was changed. Findings below are split into what was
verified against primary evidence (the live `~/.claude.json` on this machine and the
Claude Code 2.1.251 binary) and what is still open.

Evidence basis:

- `C:\Users\KyleSexton\.claude.json`, read 2026-08-31.
- `C:\Users\KyleSexton\.local\bin\claude.exe`, Claude Code 2.1.251, string-extracted.
- Repository at `origin/main` (949c54b0d).

## Part 1: what Claude Code tracks in `~/.claude.json`

`~/.claude.json` is the user-scope state file. It is a different file from
`~/.claude/settings.json` (the settings scope). It holds four usage-relevant regions.

### 1.1 `skillUsage` (machine-global, per skill)

Shape: `{"<skill name>": {"usageCount": <int>, "lastUsedAt": <epoch ms>}}`.
131 entries on this machine.

Write path in the binary (`Fdt`):

```js
let d = o.skillUsageLastWriteAt.get(t);
if (d !== void 0 && u - d < $Mn) return;          // $Mn = 60000
o.skillUsageLastWriteAt.set(t, u),
  Ae((y) => ({ ...y, skillUsage: { ...y.skillUsage,
      [t]: { usageCount: (k?.usageCount ?? 0) + 1, lastUsedAt: u } } }), r)
```

Verified properties:

- Incremented on real skill dispatch only. There is no install-time or session-start
  seeding, so a skill's `lastUsedAt` is trustworthy evidence of actual use.
- `usageCount` is a lifetime total since install. It never resets and is never windowed.
- **A 60-second per-skill throttle DROPS the increment rather than coalescing it.** A skill
  invoked five times in one minute records one. `skillUsage.usageCount` therefore
  systematically undercounts bursty skills, and the undercount is unbounded and
  unrecoverable. Contrast `pluginUsage` below, which batches and accumulates.
- Keys are inconsistent between qualified and bare form. This machine holds both
  `babysit-prs` (378) and `source-control:babysit-prs` (97) as separate rows for the
  same skill. Any consumer must sum both spellings.

### 1.2 `pluginUsage` (machine-global, per plugin)

Shape: `{"<plugin>@<marketplace>": {"usageCount": <int>, "lastUsedAt": <epoch ms>, "lastUsedNumStartups": <int>}}`.
118 entries on this machine.

Write paths in the binary:

- `Sme(e)`: batched flush, `usageCount: (d?.usageCount ?? 0) + u.count`. Accumulates, so
  unlike `skillUsage` it loses nothing to throttling.
- `yNt(e,t)`: **seeds** absent entries with `usageCount: 0`, `lastUsedAt: now`,
  `lastUsedNumStartups: <current>`.
- `dzn(e,t)`: refreshes `lastUsedAt` and `lastUsedNumStartups` on re-enable, with no
  usage.

Consequence, and the binary's own bundled skill states this explicitly: for a plugin,
`lastUsedAt` is usage evidence only when `usageCount > 0`. A zero-count plugin's
`lastUsedAt` is the seed time and means nothing.

What counts as a plugin "use" is broad. Per the binary's bundled guidance, usage is
recorded whenever a slash command, skill, agent, MCP tool or resource, or hook is
dispatched from that plugin, plus LSP servers delivering diagnostics or code navigation.
That is why hook-only plugins dominate on this machine:

| plugin | usageCount |
| --- | --- |
| `guardrails@melodic-software` | 200,804 |
| `context-guard@melodic-software` | 106,752 |
| `disk-hygiene@melodic-software` | 100,610 |
| `source-control@melodic-software` | 68,225 |

`pluginUsage.usageCount` is therefore not comparable across plugins of different shapes.
A hook plugin's count is a per-tool-call tally; a skill plugin's count is an invocation
tally. Ranking plugins by raw count ranks them by hook chattiness.

`pluginUsageLspGraceAppliedIds` (top level) records which plugin ids got the LSP grace
backfill, so a lifetime zero on an LSP-only plugin may just predate the tracking.

### 1.3 `agentLastUsed`

`{"bg": 1784439187904}` and nothing else. Subagent usage is effectively **not** tracked
here. Nothing in this repo can source agent-usage analysis from `~/.claude.json`.

### 1.4 `projects[<path>]`: per-project, last session only

28 project entries. Each carries a **snapshot of the last session in that directory**,
not a running total. Verified: `Dke(e)` builds the object fresh from live session getters
each time (`lastCost: ul(), lastAPIDuration: Xg(), ...`), and the matching telemetry event
`tengu_exit` reports these as `last_session_cost`, `last_session_api_duration`, and so on.
Each session end overwrites the previous.

Fields: `lastCost`, `lastDuration`, `lastAPIDuration`,
`lastAPIDurationWithoutRetries`, `lastToolDuration`, `lastLinesAdded`, `lastLinesRemoved`,
`lastTotalInputTokens`, `lastTotalOutputTokens`, `lastTotalCacheCreationInputTokens`,
`lastTotalCacheReadInputTokens`, `lastTotalWebSearchRequests`, `lastSessionId`,
`lastStartTime`, `lastFpsAverage`, `lastFpsLow1Pct`, `lastSessionMetrics` (frame-duration
percentiles), `lastModelUsage` (per model id: input, output, cache-read,
cache-creation tokens, web-search requests, `costUSD`).

**The decisive fact for per-project slicing:** `skillUsage` and `pluginUsage` are top
level only. Nothing under `projects` carries them. `~/.claude.json` structurally cannot
answer "which skills does this project use". Per-project cost and token data exists but
only for the single most recent session.

### 1.5 Other counters, incidental

`numStartups` (260), `promptQueueUseCount`, `btwUseCount`, `tipsHistory` and
`tipLifetimeShownCounts` (per-tip shown counts), `passesUpsellSeenCount`,
`lspRecommendationIgnoredCount`, `rcLongTurnNudgeSeenCount`. These drive tip cooldowns,
not component usage analysis.

## Part 2: the skill-listing budget scorer, recovered exactly

This is the highest-value find, because the repo currently calls it undocumented.

The scorer (`zPe`):

```js
function zPe(e) {
  let r = oe().skillUsage?.[e];
  if (!r) return 0;
  let o = (Date.now() - r.lastUsedAt) / 86400000,
      u = Math.pow(0.5, o / 7);
  return r.usageCount * Math.max(u, 0.1);
}
```

So the score is `usageCount * max(0.5 ^ (daysSinceUse / 7), 0.1)`: exponential decay with
a **7-day half-life** and a **0.1 floor**.

Where it is used (verified call sites):

1. `F1t` and the `skill_listing` attachment builder pass `(cmd) => zPe(cmd.name)` into
   `Ymt` / `Jmt` as the priority function. This is the listing-budget truncation.
2. Slash-command menu: the top 5 by `zPe` score are pinned above the alphabetical groups.
3. Slash-command search: `getScoreBoost: (c) => zPe(c.command.name)`.

The truncation algorithm (`Ymt`), verified:

- Compute each entry's full length (`name + ": " + description`, description capped).
- If total fits the budget, everyone keeps their description (`budgetMode: "fits"`).
- Otherwise sort the competing entries **descending by score**, then walk the list
  greedily granting descriptions while budget remains. Entries that do not fit go into
  `budgetTruncatedSkills` and render as `- <name>` with no description
  (`budgetMode: "priority"`).

Two corrections this forces on the repo's current wording:

- Truncation is by **decay-weighted score**, not by raw invocation count. A heavily used
  but stale skill can sort *below* a lightly used but fresh one. Concretely: 100 uses 60
  days ago scores `100 * 0.1 = 10`; 12 uses today scores `12`. The stale one loses.
- The floor means a never-used skill scores exactly `0` and always loses first, but a
  once-used skill never decays below `0.1 * usageCount`.

### Verification stamp

Follows `docs/conventions/upstream-drift`, the same shape
`plugins/source-control/hooks/worktree-create-gate.sh` uses for binary-derived claims.

- **Claim:** the scorer is `usageCount * max(0.5 ^ (daysSinceUse / 7), 0.1)`; it is the
  priority function passed to the listing-budget truncator; truncation sorts competing
  entries descending by that score and drops descriptions from the tail.
- **Basis:** string extraction of `claude.exe`, Claude Code 2.1.251, functions `zPe`,
  `Ymt`, `F1t`, `Fdt`, `Sme`, `yNt`, `dzn`, `Dke`. Confirmed against the live
  `~/.claude.json` on this machine.
- **As-of:** 2026-08-31, Claude Code 2.1.251.
- **Recheck trigger:** any release note naming the skill listing, the skill-listing budget,
  skill usage counters, or `/doctor`'s unused-component check; or the counters' shape in
  `~/.claude.json` gaining or losing a field.

This is recovered from one build of a minified bundle. Encoding it in a script means
pinning to that build, so any consumer must carry the stamp and treat a mismatch as
"scorer unknown", falling back to the current name-ordered behavior rather than asserting
a wrong ordering.

## Part 3: what this repo already has

### 3.1 Reads `~/.claude.json` counters directly

`plugins/claude-ops/skills/audit-skill-visibility/scripts/audit_skill_visibility.py` is
the only consumer of the native counters.

- `collect_native()` (line 522) reads `--claude-json`, defaulting to `~/.claude.json`.
- `parse_native()` (line 110) turns `skillUsage` rows into events, gated by
  `is_usage_evidence()` (line 68), which requires `usageCount > 0` because `lastUsedAt`
  alone is not evidence. The docstring records the measurement that justified this: 46 of
  65 plugins looked "used today" while none had been.
- `collect_jsonl()` (line 536) reads the plugin's own `skill-usage.jsonl`.
- `_reconcile()` merges the two sources by taking the max per instant rather than summing,
  so double-counting one dispatch seen by both sources is avoided.
- `compute_listing()` (line 703) does the budget arithmetic and the starvation banding.

The skill's own framing already separates certain arithmetic (does the listing overflow)
from inferential ordering (which skills lose descriptions), and labels the ordering as
resting on "an undocumented scorer pinned to one build". Part 2 above closes that gap.

### 3.2 Its own second store: `skill-usage.jsonl`

- `plugins/claude-ops/hooks/skill-usage-audit.sh`: `PostToolUse` with `matcher: "Skill"`,
  writes a `SkillUse` event per Skill tool call.
- `plugins/claude-ops/hooks/skill-usage-expansion-audit.sh`: `UserPromptExpansion`, catches
  slash-command expansions the tool hook misses.
- `plugins/claude-ops/hooks/claude-ops-paths.sh`: `claude_ops::record_skill_use`, scope
  selection (`repo` default, `user`, `data-dir`) via the `skill_usage_scope` userConfig.
- Registered at `plugins/claude-ops/hooks/hooks.json:64-88`.
- Schema and example: `docs/conventions/hook-telemetry/data/skill-usage-audit.schema.json`,
  `docs/conventions/hook-telemetry/examples/skill-usage-audit.json`.

Event shape, from the live store:

```json
{"ts":"2026-08-23T18:17:02Z","event":"SkillUse","skill":"loop","branch":"unknown",
 "project":"KyleSexton","project_id":"kylesexton-e2d95aff","hook":"skill-usage-audit",
 "source":"expansion","expansion_type":"slash_command"}
```

**This store is not redundant with `~/.claude.json`. It carries the slices the native
counters structurally lack**: `project`, `project_id`, `branch`, `source` (tool vs
expansion), `expansion_type`, and a real timestamp per event rather than one
last-used stamp. It is also immune to the 60-second throttle. The native counter owns the
global lifetime tally; the JSONL owns the sliced event stream.

### 3.3 Other usage-adjacent surfaces

- `plugins/claude-ops/skills/observability/`: OTEL DuckDB store, collector, hook-event
  JSONL, `ccusage`, cross-session trend reports.
- `plugins/claude-ops/skills/audit-install-state/scripts/install_state.py`: reads
  `~/.claude.json` for install-tree inventory, not usage.
- `plugins/claude-ops/skills/audit-performance/scripts/audit_performance.py`: reads
  `~/.claude.json` for retention-sweep health and session counts.
- `plugins/claude-config/skills/audit-permission-state/`: reads `~/.claude.json` as a
  settings scope, distinct from `~/.claude/settings.json`.
- `plugins/context-budget/skills/audit/reference/levers.json`: `~/.claude.json` as a lever
  source.
- `docs/adr/0016-source-skill-recommendation-from-the-catalog-not-the-listing.md`: the
  standing decision that skill recommendation reads the catalog, not the in-context
  listing, precisely because the listing is budget-truncated.

### 3.4 The observability skill does not read the native counters

`plugins/claude-ops/skills/observability/SKILL.md:121-122` and
`context/data-sources.md` enumerate its lanes: ccusage (tokens, cost, billing blocks),
the OTEL DuckDB store, and `.claude/observability/hook-events.jsonl` (hook duration, exit
codes). `~/.claude.json` is not among them, so the machine-global lifetime counters have
no representation in the cross-session trend reports. Its `clean` action does know about
the skill-usage store (`--skill-usage-scope`, `--keep-skill-usage-days`, default 365), but
only to prune it, never to read it.

`plugins/claude-ops/skills/audit-skill-visibility/scripts/skill-pair-cooccurrence.sh` and
`reference/pair-cooccurrence.md` derive which skills get invoked together from
`skill-usage.jsonl`. That analysis is impossible from `~/.claude.json`, which has no event
stream, and is a second reason the JSONL store earns its place.

### 3.5 What no surface covers

- No skill reasons about plugin disuse from `pluginUsage`. `claude-ops:plugins` is version
  and scope currency only; its SKILL.md and scripts never mention usage.
  `overengineering:audit` reasons about enforcement surfaces earning their keep but sources
  evidence from CI and hook behavior, not from these counters.
- Nothing reads `agentLastUsed`.
- Nothing reads `projects[<path>].lastModelUsage` or the per-project cost and token
  snapshot, despite that being the only per-project slice `~/.claude.json` offers.

### 3.6 What Claude Code itself now ships

The 2.1.251 binary contains a bundled skill that documents these exact counters and their
traps, in prose closely matching this repo's own conclusions ("`usageCount` is a LIFETIME
total since install", the `pluginUsage` seeding caveat, the qualified-vs-bare key split).
It also ships a `doctor`-side check: "Check 1: unused skills, MCP servers, and plugins",
which groups unused components against their context cost and offers to disable them
("37 unused skills, saves ~2.2k est. tokens/session"). `audit-skill-visibility`'s SKILL.md
already disclaims that one-shot check as native territory.

## Part 4: open findings, unverified or needing a decision

1. **CONFIRMED: `compute_listing` ranks on a `usage_score` nothing populates, so the
   starvation band is alphabetical.** `compute_listing` (line 703) reads
   `entry.get("usage_score", 0)` off the denominator and sorts `competing` by
   `(usage_score, qualified_name)` (line 736). The denominator is built by
   `collect_installed` / `collect_fleet_at` from a filesystem walk, which never sets
   `usage_score`. Usage events are joined to entries later, inside `classify` (line 915
   onward), after `compute_listing` has already run (line 897). Only the test fixture
   `tests/fixtures/fleet-overbudget.json` supplies non-zero values, which is why the tests
   do not catch this.

   Verified on a live run
   (`--plugins-root plugins --claude-json ~/.claude.json --render json`,
   2026-08-31): `[.skills[].starvation.usage_score] | unique` returns `[0]`. Every row
   scores zero, so the tiebreaker decides everything and bands come out in name order:

   | band | usage_score | observed count | skill |
   | --- | --- | --- | --- |
   | 1 | 0 | 1 | `adhd:clarify` |
   | 2 | 0 | 1 | `adhd:shape` |
   | 5 | 0 | 8 | `architecture:improve` |
   | 150 | 0 | 97 | `source-control:babysit-prs` |
   | 173 | 0 | 99 | `work-items:triage` |

   Band 1 is "most likely starved". The two least-used skills in the fleet are ranked as
   the first to lose their descriptions and the two most-used are ranked as the safest,
   but only because `a` sorts before `w`. The report's own inferential ordering, the part
   it warns is uncertain, currently carries no usage signal at all. Same run:
   `budget_chars` 8000, `demand_chars` 130330, `overflow_chars` 122330, 167 of 176
   competing skills marked `likely-starved`.

2. **No `skill-usage.jsonl` writes observed in this repo since 2026-08-11. Cause not
   established.** The main checkout's `.claude/observability/skill-usage.jsonl` last
   changed 2026-08-11 19:34 (107 lines) while `hook-events.jsonl` in the same directory is
   live (2026-08-31 11:27). The last `skill-usage-audit` telemetry envelope is
   `2026-08-11T23:34:24Z`. No worktree under `D:\worktrees` holds a `skill-usage.jsonl` at
   all.

   Checked and ruled out: the hook is registered
   (`plugins/claude-ops/hooks/hooks.json:64-75`), `claude-ops@melodic-software` is enabled
   in `.claude/settings.json:36`, and no `skill_usage` key (scope or kill switch) appears
   in `~/.claude/settings.json`, `.claude/settings.local.json`, or `~/.claude.json`.

   Not ruled out: the same hook did write to `~/.claude/observability/` as recently as
   2026-08-23, from a session whose resolved repo root was the home directory
   (`"project":"KyleSexton"`). So the hook itself works. Whether this repo's sessions
   stopped dispatching the `Skill` tool, or the write is landing somewhere unexpected, is
   unresolved and needs a live probe rather than more file archaeology.

3. **Nothing consumes `agentLastUsed`, and it holds one key.** Any agent-usage question has
   to come from transcripts or the OTEL store.

4. **No consumer accounts for the 60-second skill throttle.** `audit_skill_visibility.py`
   treats `usageCount` as a count of dispatches. For loop-driven or rapid-fire skills that
   is a floor, not a count. The JSONL store is the accurate source for those.

5. **No consumer accounts for the qualified-vs-bare key split.** Live data has
   `babysit-prs` and `source-control:babysit-prs` as separate rows.

## Part 5: recommendation shape

Do not rebuild a counter. `~/.claude.json` already owns the global lifetime tally, and its
scorer is now known exactly. The gaps worth closing are:

- Encode `zPe` in `audit_skill_visibility.py` and populate `usage_score` before
  `compute_listing` runs (Part 4 finding 1, plus Part 2's decay formula).
- Sum qualified and bare `skillUsage` keys.
- Keep `skill-usage.jsonl` as the per-project / per-branch / per-source slice, and fix
  whatever stopped it (Part 4 finding 2). That is the only local source for the granular
  slices the user asked about.
- Treat `pluginUsage.usageCount` as non-comparable across plugin shapes wherever it is
  ranked.
