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

### The starvation mechanism (verified against docs + the v2.1.232 bundle, 2026-08-18)

Documented verbatim in `skills.md`: *"The listing always contains every skill name, but if you have
many skills, Claude Code shortens descriptions to fit the listing's character budget… When the
listing overflows, Claude Code drops descriptions starting with the skills you invoke least, so the
skills you use most keep their full text."* Settings corroborate: descriptions for least-used skills
are dropped "so Claude can still invoke them but can't see what they do."

Four mechanics govern it, and three are traps:

- **The budget is in CHARACTERS and is DERIVED, not a constant.** `skillListingBudgetFraction`
  (default `0.01`) × context window × a hardcoded 4-bytes-per-token estimate.
  **The familiar "8,000 chars" is not a floor or a constant** — it is that formula at a 200k-token
  window. On a 1M-context model the budget is ~40,000 chars. Compute it; never hardcode 8,000.
  `SLASH_COMMAND_TOOL_CHAR_BUDGET` short-circuits the whole calculation unconditionally.
  Per-skill cap is `skillListingMaxDescChars`, default 1,536, over `description` + `when_to_use`.
- **Two classes are exempt from the contest and must not be scored as starved:** bundled prompt
  skills are force-added to the keep set and always retain full descriptions regardless of usage;
  entries set to `name-only` via `skillOverrides` are pre-excluded, and their freed bytes are NOT
  returned to the description pool. A "which skills lost their description" report built on pure
  usage ranking will misattribute both.
- **The ranking scorer is `usageCount × max(0.5^(days/7), 0.1)` — confirmed in the binary, but the
  7-day half-life and the 0.1 floor are UNDOCUMENTED implementation detail pinned to v2.1.232.**
  Reproducing it couples this skill to internals that can change in a patch release. **Prefer
  reading the ordering from `/doctor` output over reimplementing the scorer** (see Q17).
- **The overflow warning goes only to the debug log**, so a user is never told their skills were
  truncated. That silence is the reason this diagnostic has a reason to exist.

### Constraints

**Data sources — ladder, never summed.**

1. **`claude_code.skill_activated`** (OTEL, documented, first-party) — the preferred source. Carries
   `skill.name`, `skill.source`, and `invocation_trigger` (`user-slash` | `claude-proactive` |
   `nested-skill`). `invocation_trigger` is the only source that separates *"Claude never picks
   this"* from *"I never run this"*, and it closes the nested-skill attribution gap. Requires a
   collector. **Redaction vocabulary differs per event — do not filter on one literal across
   events:** on `skill_activated`, `skill.name` collapses to `custom_skill`; on the
   cost/token/`api_*` attribution attributes, user-defined skill names appear VERBATIM and only
   third-party plugin skills collapse, to `third-party`. A dashboard filtering one literal
   everywhere will under- or over-count. `skill.name` is redacted to `custom_skill` unless
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
- **Native counter mechanics that change the arithmetic** (verified in the v2.1.232 bundle): a
  60-second per-skill write debounce (`ypv=60000`) that suppresses BOTH the `usageCount` increment
  AND the `lastUsedAt` refresh — so a skill invoked every 30 s ages as though last used at the first
  call in each window — and lifetime-only counts that can never answer "used in the last 30 days".
  The in-session event still fires every time, and **`skill_activated` telemetry is NOT debounced**,
  so OTEL counts and local `usageCount` legitimately disagree. Never treat that divergence as a bug
  or reconcile it away.

**Denominator.** Installed **and enabled** — checkout, installation, and enablement are three
different sets by `claude-ops:inventory`'s own doctrine, and skills in installed-but-disabled
plugins must not be libeled. Prefer `claude_code.plugin_loaded` — the docs state it is logged "once
per enabled plugin at session start" and explicitly say to "use this event to inventory which
plugins are active across your fleet". **It fires per session start, not per install:** deduplicate
by `plugin_id_hash` (stable, unredacted, exporter-only — the correct join key for third-party
plugins) and exclude `safe_mode="true"` sessions, where the inventory is reported but nothing
actually loaded. Otherwise inventory plus an
enablement check. Call `skills/inventory/scripts/inventory.py --out` for the fleet — never
re-enumerate it. The join is not free: usage keys are `<plugin>:<leaf>`, while inventory emits bare
leaf names nested under `disk.installed_plugins[<marketplace>][<plugin>].components.skills[]`, so
the qualified name must be synthesized from the enclosing dict keys. Two marketplaces shipping a
same-named plugin collapse to one usage key — detect and report the ambiguity rather than
misattributing.

**Classification.** Ground every cold verdict in the **15 evidenced never-auto-invoked causes, 11 of
them genuinely silent** (skill looks fine, is never selected, and nothing surfaces outside
`--debug`). **Correction, verified 2026-08-18:** there is NO official 13-reason list — `skills.md`
Troubleshooting is a 4-item checklist. The 15-cause table is assembled from scattered doc sections
plus binary strings and MUST be labeled that way in any user-facing output; never cite it to a user
as documented. Silent causes evidenced include malformed frontmatter YAML (body loads with empty
metadata, `/name` still works, parse error only under `--debug`), an omitted `description` falling
back to the first body paragraph, description + `when_to_use` truncated past 1,536 chars, a synced
claude.ai skill whose name collides with any other command (skipped entirely; matching ignores case,
spacing, invisible chars, and fullwidth/dash variants), dot-prefixed skills-dir entries, and reduced
mode skipping skill discovery wholesale.
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
2. **Superseded 2026-08-18 by design thread T3** (user-approved). Was: "resolves to exactly one
   reach state, including `not observable`." Now: every skill in the enabled denominator resolves to
   exactly one value on EACH of three independent fields — `reachability`, `observation`,
   `starvation`. Type modeling showed a single enum collapses *can the model select this* with
   *have we observed it*, and misfiles bundled skills (model-reachable, but exempt from the
   description contest) as unreachable. See `design/contracts.md`.
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
- The decay scorer's 7-day half-life and 0.1 floor are confirmed present in the v2.1.232 bundle but
  are UNDOCUMENTED and unversioned — never present a starvation cutoff derived from them as exact,
  and re-verify on each Claude Code upgrade. This is the single highest-risk dependency in the
  design.
- The "documented reasons a skill is never auto-invoked" framing was WRONG in the pre-verification
  draft of this Brief: no such official list exists. Corrected above to 15 evidenced causes with
  their provenance stated.
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

**Scale:** medium-large (new skill + shared-harness change + 9-file registration).
**Technique:** tracer bullet / walking skeleton — the design unknowns were resolved upstream
(`design/`), and the remaining risk is *integration* across four data sources, so Phase 1 is a thin
end-to-end slice that runs for real, not a horizontal layer.
**Standards grounded:** repo `CLAUDE.md`; `docs/PLUGIN-PHILOSOPHY.md` (naming grammar, cross-plugin
boundary); `docs/conventions/plugin-data-report-keying/`; `docs/conventions/hook-budget/`;
`docs/extensibility-contract-smoke-tests.md` Test B; registration precedent commit `4a1184cd`.
**TDD:** Red-Green-Refactor per phase. The pure classifier is the unit seam; `*.test.sh` covers the
CLI surface. Tests ride each phase — there is no "testing phase".

### Phase 1: Walking skeleton — end-to-end at T-baseline [TODO]

The integration slice. Denominator → one source → three-field model → markdown, running for real.

- Create `plugins/claude-ops/skills/audit-skill-starvation/SKILL.md` (frontmatter per the
  `observability`/`inventory` pair; `metadata.workflow-stage: operator`, `cadence: weekly`).
- `scripts/collect.sh`: call `inventory.py --out` for the fleet; synthesize `<plugin>:<leaf>` from
  the nested dict keys; read native `skillUsage`, checking BOTH the qualified key and the bare-name
  fallback.
- `scripts/classify.*`: **pure** — `(denominator, events, config, clock) → model`. Emits the
  `observation` field plus `withheld`. Clock is injected; nothing reads wall-clock inside.
- `scripts/render.sh`: markdown only at this phase; prints every source horizon.
- Honesty floor live from the first commit: `observed_horizon` per source, tiers clamped to it,
  `not-observable` as the default verdict, exposure floor (30d created / 7d inactive) suppressing
  cold verdicts.
- Tests (red first): horizon-shorter-than-window → nothing renders `dormant`; empty store +
  populated native → `not-observable`, never "never used"; install-seeded `pluginUsage` row → never
  read as usage or recency.
- **Sanity Check:** `bash plugins/claude-ops/skills/audit-skill-starvation/scripts/render.sh` exits 0
  and its output matches `grep -q "observed_horizon"`; on this 3-day-old container the run reports
  `not-observable` for the bulk of the fleet rather than a "never used" wall.
  `bash plugins/claude-ops/skills/audit-skill-starvation/*.test.sh` exits 0.

### Phase 2: Reachability — the frontmatter and enablement pass [TODO]

`inventory.py` emits bare names with no frontmatter, so reachability needs its own read. This does
NOT re-enumerate the fleet — it reads frontmatter only for skills inventory already named.

- Frontmatter pass over each named skill's `SKILL.md`: `disable-model-invocation`, `description`
  presence and length, `when_to_use`, malformed-YAML detection.
- Enablement: prefer `claude_code.plugin_loaded` when present (dedupe by `plugin_id_hash`, exclude
  `safe_mode="true"`); else the settings-scope enablement check.
- Emit `reachability` as one of `model-reachable` / `user-only` / `hidden` / `misconfigured` /
  `unknown`, with `misconfigured` carrying its sub-cause list and evidence.
- Every rendered cause is labeled with provenance — assembled from scattered docs plus binary
  strings, **never** presented as an official list.
- Tests: a `disable-model-invocation` skill resolves `user-only`, not "unused"; malformed YAML
  resolves `misconfigured` with fix-me copy, never a removal candidate; undetermined → `unknown`.
- **Sanity Check:** run against this repo; `grep -c '"reachability"'` on the JSON equals the skill
  count, and `grep -c 'user-only'` is at least 55 (59 of 213 local skills set
  `disable-model-invocation`; 55 absorbs churn). No row renders `misconfigured` alongside removal
  wording — a `grep -i "delete\|remove"` returns no line that also matches `misconfigured`.

### Phase 3: Starvation — budget arithmetic, then the inferential band [TODO]

- **Certain half:** budget = `skillListingBudgetFraction` (default 0.01) × context window ×
  4 bytes/token, with `SLASH_COMMAND_TOOL_CHAR_BUDGET` overriding unconditionally. **Compute it —
  never hardcode 8,000.** Demand = the sum of `description` + `when_to_use` per skill, each capped at
  `skillListingMaxDescChars` (default 1,536), over the **competing set only**.
- Exemptions applied before the sum: bundled prompt skills are exempt; `skillOverrides: name-only`
  entries are excluded and their freed bytes are NOT returned to the pool.
- `overflow_chars > 0` proves truncation → report magnitude and approximate name-only count. This is
  the headline finding, and it needs no undocumented constant.
- **Inferential half:** rank the competing set by the observable proxy; render a band, never a
  cutoff; label it inferential; never claim exactness.
- Tests: demand just under and just over budget (boundary); bundled + name-only excluded from both
  the sum and the ranking; a 1M-token context window yields ~40,000 chars, not 8,000.
- **Sanity Check:** a fixture pinning a 1M-token context asserts `budget_chars == 40000` (regression
  guard on the derived-not-constant correction); `overflow_chars` sign matches each boundary
  fixture; any band output satisfies `grep -q "inferential"`.

### Phase 4: Source ladder — T-local and T-full [TODO]

- Add the `skill-usage.jsonl` collector (scope-resolved via `claude_ops::resolve_skill_usage_dir`,
  all three scopes) and the OTEL `claude_code.skill_activated` collector.
- Tier resolution `T-full` / `T-local` / `T-baseline`; a claim renders only at a supporting tier, and
  the run states its tier and why.
- Reconciliation rule applied and printed — `max()` per skill, or native-for-lifetime and
  JSONL-for-attribution. **Never sum.** OTEL-vs-native divergence is expected (telemetry is not
  debounced; the native counter is) and is never reconciled away.
- **No dedupe pass** — the hook writes one destination per invocation, and id-less
  second-granularity rows would collapse genuine same-second invocations.
- Redaction handled per event: `custom_skill` on `skill_activated`; `third-party` on the cost/token
  attribution attributes, where user-defined names appear verbatim.
- Tests: the same event present in native + JSONL is counted once, never summed; two genuine
  same-second invocations count twice; a cross-marketplace same-leaf collision yields
  `ambiguous-attribution`.
- **Sanity Check:** the double-count fixture asserts the reconciled total equals the max and not the
  sum; `jq -e '.tier' <json>` exits 0 and its value matches the sources actually present.

### Phase 5: Outputs — keying, JSON, optional HTML [TODO]

- Add `plugins/claude-ops/lib/state-key.sh` (claude-ops's first `lib/`), adopting the registered
  helper rather than minting a second keying scheme.
- JSON per `plugin-data-report-keying` Rule 1: one file per run **plus** an appended history line;
  never a rolling `latest.json`. `schema_version`, additive-only.
- `withheld` rendered as a first-class section in both markdown and JSON.
- Optional self-contained HTML at larger scopes, mirroring observability's precedent; markdown stays
  the durable record.
- **Sanity Check:** the written path matches
  `${CLAUDE_PLUGIN_DATA}/<component>/<repo-identity>/<worktree-discriminator>/` — assert with `find`
  plus a regex; two consecutive runs produce two files and grow the history file by exactly one line
  (`wc -l`); `jq -e '.withheld' <json>` exits 0.

### Phase 6: Retention, routing, and registration [TODO]

Touches at least 10 files — inventory table required.

| File | Action | Rationale |
|---|---|---|
| `skills/observability/scripts/clean.sh` | MODIFY | prune `skill-usage.jsonl` via the hooks' path policy across `repo`/`user`/`data-dir`; needs its own retention flag (`--keep-days` is single-valued today) |
| `skills/observability/SKILL.md` | MODIFY | retention table (1 of 4 locations) |
| `skills/observability/context/read-routing.md` | MODIFY | retention table + the skill-reach routing row |
| `skills/observability/context/operator-setup-retention.md` | MODIFY | retention table |
| `.claude-plugin/plugin.json` | MODIFY | MINOR version bump; `"Ten skills"` → `"Eleven skills"` plus an enumeration clause |
| `README.md` | MODIFY | intro count ten → eleven; one `## Skills` row. **Never hand-edit the generated options block** |
| `CHANGELOG.md` | MODIFY | entry per precedent |
| `docs/CATALOG.md` | REGENERATE | `node scripts/generate-catalog.mjs` |
| `docs/SKILL-CHEAT-SHEET.md` | REGENERATE | `node scripts/generate-cheatsheet.mjs` |
| `skills/audit-skill-starvation/evals/evals.json` | CREATE | per-skill evals, matching the reference pair |
| `.claude-plugin/marketplace.json` | KEEP | its entry carries no skill enumeration — precedent `4a1184cd` did not touch it |
| `docs/CATALOG-TAXONOMY.md` | KEEP | governs plugin categories, not skills; `claude-ops` is already `claude-code` |
| `scripts/skill-leaf-name-registry.txt` | KEEP unless colliding | registering a non-colliding leaf is itself a CI failure |

- **Sanity Check:** `bash scripts/check-skill-leaf-names.sh --check` exits 0;
  `node scripts/generate-catalog.mjs --check` and `node scripts/generate-cheatsheet.mjs --check` exit
  0; `python3 scripts/check-manifest-duplicate-keys.py` exits 0;
  `python3 scripts/sync-plugin-options-docs.py --check` exits 0;
  `claude plugin validate plugins/claude-ops` exits 0;
  `grep -c "Eleven skills" plugins/claude-ops/.claude-plugin/plugin.json` equals 1; and
  `clean.sh --dry-run` reports a skill-usage target under a `user`-scope fixture, proving the
  silent-no-op defect is fixed.

## Blast radius

**MEDIUM-HIGH.** A new module plus a change to a *shared* harness (`clean.sh`) that other skills'
retention depends on, plus generated catalog surfaces gated in CI. Mitigating: the skill is
read-only, adds no hooks, and the only mutation anywhere in the change is one added pruning target.

## Open questions

- **Q18 (USER-RESERVED) — session transcripts in V1?** Surfaces at this approval gate, undecided.
- **Q19 — leaf name** `audit-skill-starvation`: confirm via `scripts/check-skill-leaf-names.sh`.
