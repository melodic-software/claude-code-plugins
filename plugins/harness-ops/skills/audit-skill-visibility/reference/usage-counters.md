# The `~/.claude.json` usage counters

Read this when a count this skill reports looks wrong, or before writing a new
consumer of these counters. It records what each region actually means, and the
four traps that make a naive read wrong. `~/.claude.json` is the user-scope state
file, a different file from `~/.claude/settings.json`.

Companion: [listing-scorer.md](listing-scorer.md), which covers how the product
ranks these counts when it truncates the skill listing.

## Verification stamp

Follows `docs/conventions/upstream-drift`.

- **Claim:** the write paths, seeding behavior, and per-region semantics below.
- **Basis:** string extraction of `claude.exe` at Claude Code 2.1.251, the write
  and read functions named per region, confirmed against a live `~/.claude.json`.
  Scorer and truncator re-verified unchanged at 2.1.252.
- **As-of:** 2026-08-31.
- **Locate by shape, never by name.** Minified identifiers move between builds;
  the listing scorer was `zPe` at 2.1.251 and `WPe` at 2.1.252 with an identical
  body. Grep the arithmetic and the field names, not the function names.
- **Recheck trigger:** a release note naming skill usage counters, the skill
  listing, or `/doctor`'s unused-component check; or these keys gaining or losing
  a field.

## `skillUsage`, machine-global, per skill

`{"<skill name>": {"usageCount": <int>, "lastUsedAt": <epoch ms>}}`

Write path, reduced to its decisive lines:

```js
let d = o.skillUsageLastWriteAt.get(t);
if (d !== void 0 && u - d < 60000) return;
o.skillUsageLastWriteAt.set(t, u),
  Ae((y) => ({ ...y, skillUsage: { ...y.skillUsage,
      [t]: { usageCount: (k?.usageCount ?? 0) + 1, lastUsedAt: u } } }), r)
```

- Written on real skill dispatch only. **No install-time or session-start
  seeding**, so a skill's `lastUsedAt` is trustworthy evidence of actual use.
  This is the one place it is trustworthy; see `pluginUsage` below.
- `usageCount` is a lifetime total since install. It never resets and is never
  windowed, which is why the engine's `T-baseline` tier supports a lifetime
  claim and refuses a windowed one.
- **The 60-second per-skill throttle DROPS the increment, it does not coalesce
  it.** A skill invoked five times in one minute records one. The undercount is
  unbounded and unrecoverable, so for loop-driven or rapid-fire skills this
  counter is a floor rather than a count. Divergence from OTEL is expected here
  and must not be reconciled away.
- **Keys are inconsistent between qualified and bare form.** One machine held
  both `babysit-prs` (378) and `source-control:babysit-prs` (97) as separate rows
  for the same skill. Every consumer has to resolve both spellings. Note that the
  product's own listing scorer does NOT do this fallback, which is why the
  starvation band deliberately does not either.

## `pluginUsage`, machine-global, per plugin

`{"<plugin>@<marketplace>": {"usageCount": <int>, "lastUsedAt": <epoch ms>, "lastUsedNumStartups": <int>}}`

Three write paths, and the second is the trap:

- Batched flush accumulates: `usageCount: (d?.usageCount ?? 0) + u.count`. Unlike
  `skillUsage`, nothing is lost to throttling.
- Absent entries are **seeded** with `usageCount: 0`, `lastUsedAt: now`,
  `lastUsedNumStartups: <current>` on install or enable.
- `lastUsedAt` and `lastUsedNumStartups` are **refreshed on re-enable**, with no
  usage at all.

So for a plugin, `lastUsedAt` is usage evidence only when `usageCount > 0`. A
zero-count plugin's `lastUsedAt` is the seed time and means nothing. Measured on
one machine: 46 of 65 plugins looked "used today" while none had been used. That
measurement is what `is_usage_evidence()` in the engine exists to enforce.

**A plugin "use" is broad and not comparable across plugin shapes.** Usage is
recorded whenever a slash command, skill, agent, MCP tool or resource, or hook is
dispatched from that plugin, plus LSP servers delivering diagnostics or code
navigation. Hook-only plugins therefore dominate any raw ranking: on one machine
`guardrails` showed 200,804 and `context-guard` 106,752, against low hundreds for
skill-shaped plugins. A hook plugin's count is a per-tool-call tally; a skill
plugin's count is an invocation tally. Ranking plugins by raw count ranks them by
hook chattiness, not by value.

`pluginUsageLspGraceAppliedIds` at the top level records which plugin ids got the
LSP grace backfill, so a lifetime zero on an LSP-only plugin may simply predate
the tracking.

## `agentLastUsed`

Observed holding a single key (`bg`). Subagent usage is effectively **not tracked
here**, so no agent-usage analysis can be sourced from this file. The transcript
parsers in the session-flow retro skills are the working source for that.

## `projects[<path>]`, per-project, last session only

Each entry is a **snapshot of the last session in that directory, not a running
total**. The object is rebuilt from live session getters at each write, and the
matching exit telemetry reports the same values as `last_session_*`. Every
session end overwrites the previous one.

It carries cost, wall and API durations, lines added and removed, the four token
totals, web-search requests, session id and start time, frame-duration
percentiles, and `lastModelUsage` broken down per model id.

**The decisive fact for per-project usage questions:** `skillUsage` and
`pluginUsage` are top level ONLY. Nothing under `projects` carries them, so this
file structurally cannot answer "which skills does this project use". That
question needs the plugin's own `skill-usage.jsonl` store, whose rows carry
`project`, `project_id`, and `branch`, or OTEL.

## Growth, and the one supported shrink lever

The file is never swept: `cleanupPeriodDays` does not reach it, because it lives
in the home directory rather than under `~/.claude`. The supported lever is
`claude project purge <path>`, which removes one project's entry. Every running
session polls the file at 1 Hz, and the strongest public report of curing input
lag pruned this file rather than the install tree.

`.claude.json.tmp.<n>.<hash>` siblings are failed atomic-write remnants; the
leading number only looks like a PID. See
[`audit-install-state/reference/surfaces.md`](../../audit-install-state/reference/surfaces.md)
for the install-tree side of this, which holds the file stat-only because its
values can carry tokens.

## Incidental counters, not usage signals

`numStartups`, `promptQueueUseCount`, `tipsHistory`, `tipLifetimeShownCounts`,
`passesUpsellSeenCount`, `lspRecommendationIgnoredCount`. These drive tip
cooldowns and onboarding state, not component usage analysis.
