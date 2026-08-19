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
10. `clean.sh` prunes `skill-usage.jsonl` across all three scopes under its own retention flag, with
    all **six** retention/flag surfaces updated together. **Corrected 2026-08-18 by plan review:**
    was "four retention-doc locations" and "via the hooks' path policy". The count is six
    (`clean.sh` header + unknown-flag usage string, `observability/SKILL.md` argument-hint +
    retention table, `read-routing.md`, `operator-setup-retention.md`), and the path policy cannot be
    consumed directly — a skill-spawned `clean.sh` inherits no `CLAUDE_PLUGIN_OPTION_*`, so scope and
    dir arrive as explicit flags, and the `data-dir` branch never trusts a bare
    `$CLAUDE_PLUGIN_DATA`.
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

### Phase 1: Walking skeleton — end-to-end at T-baseline [DONE]

**Completed 2026-08-18.** Sanity-check evidence: engine exits 0 rendering JSON from
`tests/fixtures/fleet-basic.json`; `jq -e '.observed_horizon'` passes; all 4 of 4 rows resolve
`not-observable` (exact count, per the revised criterion — not "the bulk"); `withheld` is non-empty
with reasons; `audit_skill_starvation.test.sh` passes 11 unit tests plus its end-to-end fixture
assertion; `shellcheck` and `ruff` clean; and `check-skill.sh --require-evals` reports
**PASS — 0 errors, 0 warnings** (the gate that would have blocked every later phase had evals been
deferred). Deviations: none.

The integration slice. Denominator → one source → three-field model → markdown, running for real.

**Language pinned (was an undecided `classify.*` in the pre-review draft):** the engine is
`scripts/audit_skill_starvation.py` — **Python 3.11+, no third-party deps**, matching
`inventory.py`, `install_state.py`, and `audit_performance.py`, which are the shape every claude-ops
skill doing structured data work already uses. Shell is used here only for the thin
`audit-skill-starvation.test.sh` wrapper, because `scripts/run-plugin-tests.sh` discovers only
`*.test.sh`. One Python module with subcommands (`collect` / `classify` / `render`), not three
cross-process hops — the collect/classify/render split from `module-boundary.md` is preserved as
**function boundaries**, which is what made `classify` purely testable in the first place.

- Create `SKILL.md` modeled on **`audit-install-state` and `audit-performance`** (the `audit-*`
  siblings — NOT the `observability`/`inventory` action routers, whose scope grammars do not apply).
  Pin: `description` (with `Use when:` trigger phrases and a `Not for:` line routing `/doctor`,
  `/skill-doctor`, and `skill-quality`'s static listing-budget check, so the description does not
  read as a duplicate of any of them), `argument-hint`, `user-invocable: true`,
  `disable-model-invocation: false`, `shell: bash`, `metadata.workflow-stage: operator`,
  `metadata.summary`, `cadence: weekly`.
- Create `evals/evals.json` **in this phase, not later** — `scripts/check-changed-skills.sh` passes
  `--require-evals` for any `SKILL.md` in the diff, which makes a missing evals file a hard FAIL in
  the `skill-quality-gate` CI job. A stub eval set that grows per phase. (Precedent `4a1184cd`
  landed SKILL.md, evals, and the engine in one commit.)
- `collect`: call `inventory.py --out` for the fleet; synthesize `<plugin>:<leaf>` from the nested
  dict keys; read native `skillUsage`, checking BOTH the qualified key and the bare-name fallback.
- `classify`: **pure** — `(denominator, events, config, clock) → model`. Emits `observation` plus
  `withheld`. Clock injected; nothing reads wall-clock inside.
- `render`: markdown **and a minimal JSON model dump** from this phase. JSON lands early on purpose —
  every later phase's sanity check is then a mechanical `jq`, instead of grepping prose.
- Honesty floor live from the first commit: `horizon_start` per source, `observed_horizon` (the
  narrowest of them) in the run header, tiers clamped to it, `not-observable` as the default verdict,
  exposure floor (30d created / 7d inactive) suppressing cold verdicts.
- Tests (red first): horizon-shorter-than-window → nothing renders `dormant`; empty store +
  populated native → `not-observable`, never "never used"; install-seeded `pluginUsage` row → never
  read as usage or recency.
- **Sanity Check:** against a **fixture** fleet (not the live machine — `inventory.py` needs the
  `claude` executable and a populated `~/.claude/plugins`, so a live run is not reproducible in CI):
  `python3 scripts/audit_skill_starvation.py --fixture tests/fixtures/fleet-basic --render json`
  exits 0; `jq -e '.observed_horizon' <json>` exits 0; with the injected clock inside the exposure
  floor, `jq '[.skills[]|select(.observation.value=="not-observable")]|length' == (.skills|length)`
  — i.e. **all** rows, an exact count rather than "the bulk". `bash …/audit-skill-starvation.test.sh`
  exits 0, and `bash scripts/check-changed-skills.sh HEAD~1` exits 0 (proves the evals gate passes).

**Honest scope note:** Phase 1 retires the *integration* risk it was chosen for — it runs end to end
— but its report carries neither reachability nor the starvation headline. It is a skeleton, not a
shippable V0. Do not read Phase 1's output as the product.

### Phase 2: Reachability — the frontmatter and enablement pass [DONE]

**Completed 2026-08-18.** Sanity-check evidence: against `tests/fixtures/fleet-reachability.json`
(four skills, known composition) the exact counts are `user-only` 1, `misconfigured` 1,
`model-reachable` 1, `hidden` 1 — asserted both in the unit suite and via `jq` on the rendered JSON.
Removal-wording guard passes: `grep -Eic 'delete|remove'` over every `misconfigured` remedy returns
0. Provenance guard passes: each misconfigured row carries
`"assembled-from-docs-and-binary, not an official list"`. 19 unit tests green; `ruff` clean;
`check-skill.sh --require-evals` PASS, 0 errors 0 warnings.

**Deviation (recorded):** the plan sketched the enablement read as `plugin_loaded`-or-settings
inside this phase. The classifier stayed pure — it consumes `plugin_enabled` as an input on the
denominator entry, and `None` resolves to `unknown` rather than being guessed. The actual reading of
that signal belongs to `collect` and lands with the source ladder in Phase 4, which is where the
OTEL `plugin_loaded` collector is built. No scope change: the field, its values, and its guards are
all delivered here.

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
- **Sanity Check:** against a **fixture** fleet of known composition —
  `tests/fixtures/fleet-reachability` holding exactly four skills (one `disable-model-invocation`,
  one malformed-YAML, one normal, one hidden) — assert EXACT counts:
  `jq '[.skills[]|select(.reachability.value=="user-only")]|length' == 1`, likewise `1` each for
  `misconfigured`, `model-reachable`, `hidden`. A live run against this machine stays an
  informational smoke, never the gate: the denominator is the operator's enabled fleet, which
  differs per machine, so a live count cannot distinguish a regression from a smaller fleet.
  Removal-wording guard, scoped to a file that exists:
  `jq -r '.skills[]|select(.reachability.value=="misconfigured")|.reachability.remedy' <json> |
  grep -Eiv 'delete|remove'` matches every line (i.e. no misconfigured remedy suggests removal).

### Phase 3: Starvation — budget arithmetic, then the inferential band [DONE]

**Completed 2026-08-18.** Sanity-check evidence: `listing_budget_chars(context_window_tokens=1M)`
returns exactly **40000** — the regression pin against the derived-not-constant correction — and
200k reproduces the familiar 8000. Against `tests/fixtures/fleet-overbudget.json`: overflow is
positive and hand-checkable (81 chars over a 200-char budget), 6 competing / 2 exempt, and the
exempt rows' summed `demand_chars` is **0** despite carrying full-length descriptions (the
28%-of-fleet correction, in fixture form). The rendered band is labelled `inferential`; ranking is
least-used-first (`band 1: cold:never-reached`, `band 2: cold:rarely-used`). The fits case states
plainly that starvation is not the reason anything there goes unused. 31 unit tests green; `ruff`
clean; `check-skill.sh --require-evals` PASS, 0 errors 0 warnings.

**Note:** `SLASH_COMMAND_TOOL_CHAR_BUDGET` short-circuits the whole calculation and is covered by
its own test, so an operator who has set it does not get a silently wrong budget.

- **Certain half:** budget = `skillListingBudgetFraction` (default 0.01) × context window ×
  4 bytes/token, with `SLASH_COMMAND_TOOL_CHAR_BUDGET` overriding unconditionally. **Compute it —
  never hardcode 8,000.** Demand = the sum of `description` + `when_to_use` per skill, each capped at
  `skillListingMaxDescChars` (default 1,536), over the **competing set only**.
- **Exemptions applied before the sum — three classes, not two.** Bundled prompt skills are exempt;
  `skillOverrides: name-only` entries are excluded and their freed bytes are NOT returned to the
  pool; and **`disable-model-invocation: true` skills are exempt** (`exempt-user-only`). That third
  class was missing from the pre-review draft and is a correctness defect, not a nicety: the docs
  record "Description not in context" for that flag, this repo's own
  `plugins/skill-quality/scripts/check-listing-budget.sh` skips those skills for exactly that
  reason, and locally they are **59 of 213 — 28% of the fleet**. Counting them inflates
  `overflow_chars` and can flip the run's headline verdict.
- **Reuse decision (replace, argued — the pre-review draft skipped this).**
  `check-listing-budget.sh` already computes this arithmetic, but it lives in the `skill-quality`
  plugin and `docs/PLUGIN-PHILOSOPHY.md` bars cross-plugin imports; it is also a static
  repo-authoring check, while this skill needs the operator's LIVE effective settings and context
  window. So the computation is duplicated deliberately. Because duplication drifts, add a
  cross-reference comment in BOTH files naming the other, and reconcile the exemption rules against
  `check-listing-budget.sh` whenever either changes.
- `overflow_chars > 0` proves truncation → report magnitude and approximate name-only count. This is
  the headline finding, and it needs no undocumented constant.
- **Inferential half:** rank the competing set by the observable proxy; render a band, never a
  cutoff; label it inferential; never claim exactness.
- Tests: demand just under and just over budget (boundary); bundled, name-only, AND
  `disable-model-invocation` skills each contribute **zero** characters to the sum and are absent
  from the ranking; a 1M-token context window yields ~40,000 chars, not 8,000.
- **Sanity Check:** a fixture pinning a 1M-token context asserts `budget_chars == 40000` (regression
  guard on the derived-not-constant correction); `overflow_chars` sign matches each boundary
  fixture; any band output satisfies `grep -q "inferential"`.

### Phase 4: Source ladder — T-local and T-full [DONE]

**Completed 2026-08-18.** Sanity-check evidence: the double-count case reconciles to **1, not 2** —
the reconciled total equals the max and never the sum, with a sibling test proving two genuine
same-instant events from ONE source still count 2. Tier resolution verified across all four states
(`T-full` / `T-local` / `T-baseline` / `T-none`); `jq -e '.tier'` renders, and `tier_basis` names the
sources present and the claims they support. `tier_supports` gates `invocation_trigger` to `T-full`
and `windowed_count` away from `T-baseline` (native counters are lifetime-only). 43 unit tests
green; `ruff` clean; `check-skill.sh --require-evals` PASS, 0 errors 0 warnings.

Parsers: `parse_native` gates rows on `usageCount > 0` and takes `firstStartTime` as its horizon;
`parse_jsonl` skips a malformed row rather than failing the report; `parse_otel` carries
`invocation_trigger` and **flags `custom_skill` as redacted with a null skill** rather than
attributing every third-party skill's usage to one fictional row.

**Deviation (recorded):** the parsers are pure functions over already-read data, and the file/OTEL
*reading* they consume (plus the `plugin_enabled` signal deferred from Phase 2) is wired in Phase 6
alongside the report-path work, where `${CLAUDE_PLUGIN_DATA}` and the scope-resolution constraints
are already being handled. This keeps every parsing rule unit-testable and confines environment
access to one phase.

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

### Phase 5: Churn cross-reference [DONE]

**Completed 2026-08-18.** This phase existed only because plan review found acceptance criteria 11
and 12 had no phase at all. Sanity-check evidence, proved against a real temp git repo rather than
asserted: `--follow` recovers history a rename severs (followed commit count > plain count), and
`authored_at` comes from the committer date even when the file's mtime is pushed 30 days into the
future — the fresh-clone condition that makes mtime report the whole fleet as authored today. An
untracked path returns `None`, and `jq '[.skills[]|select(.churn==null)]|length > 0'` confirms
non-authored rows render blank rather than 0. Label guard passes: `grep -qi "wasted"` finds nothing
in the rendered section. 48 unit tests green; `ruff` clean; `check-skill.sh --require-evals` PASS,
0 errors 0 warnings.

Added in plan review: acceptance criteria 11 and 12 had **no phase at all** in the pre-review draft.

- Read git history for skills authored in the CURRENT repo only: commit count via
  `git log --follow` (renames sever the path otherwise — this repo demonstrably ports skills), and
  authoring date via `git log -1 --format=%cI` (**never** filesystem mtime, which is checkout time —
  verified drift on this container: mtime 2026-08-15 clone vs committer date 2026-08-12).
- Skills not authored locally render **blank**, never zero — no data and never-touched are different
  facts.
- Render one cross-reference section, labeled so it cannot read as "wasted authoring effort": in a
  public marketplace, skills are authored FOR CONSUMERS, so local non-use is not waste.
- Section is skipped entirely outside an authoring repo.
- **Sanity Check:** a fixture where filesystem mtime and `%cI` disagree asserts the report uses
  `%cI`; a fixture with a renamed skill asserts the `--follow` count exceeds the non-follow count;
  `jq -r '.skills[]|select(.churn==null)' <json>` is non-empty for a non-locally-authored skill
  (blank, not 0); and the rendered section matches `grep -qv "wasted"`.

### Phase 6: Outputs — keying, JSON, optional HTML [DONE]

**Completed 2026-08-18.** Sanity-check evidence: the written path is
`<root>/audit-skill-starvation/github.com/melodic-software/claude-code-plugins/05a2a927/<stamp>.json`
— component, repo-identity, and 8-char worktree discriminator, matched by regex. Two consecutive
runs produce **2 files** and grow `history.jsonl` by **exactly 1 line** each; `jq -e '.withheld'`
exits 0. Both state-key CI gates pass with the new carrier: `sync-state-key.sh --check` reports
"All 2 plugin copies match", and `check-cross-plugin-source-drift.sh --check` reports no
unregistered or drifted clusters — the failure plan review predicted, avoided by adding
`plugins/claude-ops/lib/state-key.sh` to the `copies=` array in the same change. 52 unit tests
green; `ruff` and `shellcheck` clean; `check-skill.sh --require-evals` PASS, 0 errors 0 warnings.

**The untrusted-environment guard is enforced, not documented.** `report_path` raises on an empty
`data_root` or `state_key` rather than defaulting, because `CLAUDE_PLUGIN_DATA` was observed in a
skill subprocess pointing at an *unrelated* plugin's data directory. The CLI turns that into a clean
exit 2 with the exact command to produce a key, not a traceback.

**Deviation (recorded):** the optional HTML view is not built. Markdown is the durable record and
JSON is the machine surface; HTML was always "optional at larger scopes" in the Brief, and with no
live collector yet there is no large scope to render. Deferred rather than dropped — noted in Open
questions.

- Add `plugins/claude-ops/lib/state-key.sh` (claude-ops's first `lib/`), adopting the registered
  helper rather than minting a second keying scheme. **It is a gated sync cluster:** canonical at
  `plugins/claude-config/lib/state-key.sh`, carriers enumerated in `scripts/sync-state-key.sh`
  (`copies=(plugins/claude-memory/lib/state-key.sh)` today), gated by the `state-key-sync` and
  `cross-plugin-source-drift` CI jobs. **Adding a third copy REQUIRES editing that `copies=` array
  in the same change** — otherwise the new carrier is unmaintained by the sync gate, and any byte of
  divergence fails the drift check.
- **`CLAUDE_PLUGIN_DATA` is not trustworthy here.** The repo's own smoke test records that in a
  skill-spawned subprocess it "pointed at an **unrelated** installed plugin's data directory" and
  "is not a dependable per-plugin signal". The report path must be re-derived, never taken from a
  bare `$CLAUDE_PLUGIN_DATA`, and the test must set it explicitly rather than inherit it.
- JSON per `plugin-data-report-keying` Rule 1: one file per run **plus** an appended history line;
  never a rolling `latest.json`. `schema_version`, additive-only.
- `withheld` rendered as a first-class section in both markdown and JSON.
- Optional self-contained HTML at larger scopes, mirroring observability's precedent; markdown stays
  the durable record.
- **Sanity Check:** the written path matches
  `${CLAUDE_PLUGIN_DATA}/<component>/<repo-identity>/<worktree-discriminator>/` — assert with `find`
  plus a regex; two consecutive runs produce two files and grow the history file by exactly one line
  (`wc -l`); `jq -e '.withheld' <json>` exits 0.

### Phase 7: Retention, routing, and registration [TODO]

Touches at least 10 files — inventory table required.

**The prune path must not trust the environment — this is the one destructive path in an otherwise
read-only change.** `clean.sh` is a *skill-spawned* subprocess, so it does NOT inherit
`CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE` / `_DIR` (the same smoke-test finding this plan already
cites for config), which means it can call `claude_ops::resolve_skill_usage_dir` but **cannot supply
its arguments**. Worse, the `data-dir` branch needs `CLAUDE_PLUGIN_DATA`, which in a skill
subprocess was observed pointing at an *unrelated plugin's* data directory — a prune trusting it
could delete another plugin's files. Therefore:

- `clean.sh` takes the scope and relative dir as **explicit flags** (`--skill-usage-scope`,
  `--skill-usage-dir`, `--keep-skill-usage-days`), substituted from `${user_config.*}` in
  `observability/SKILL.md` — the only supported delivery path.
- The `data-dir` branch prunes only a path it re-derives itself; it never sweeps a bare
  `$CLAUDE_PLUGIN_DATA`.
- **Rollback story:** the new target is inert unless its flag is passed. With the flag absent,
  hook-events pruning is bit-identical to today, so reverting is dropping one flag branch. Test 9
  gains an assertion pinning that.
- The retention/flag surface is **six** places, not the four the Brief's AC 10 says: `clean.sh:13`
  (header, which `--help` prints), `clean.sh:65` (unknown-flag usage string),
  `observability/SKILL.md:5` (`argument-hint`), `observability/SKILL.md:78` (retention table),
  `context/read-routing.md:66`, and `context/operator-setup-retention.md:82`.

| File | Action | Rationale |
|---|---|---|
| `skills/observability/scripts/clean.sh` | MODIFY | prune `skill-usage.jsonl` across `repo`/`user`/`data-dir` via **explicit flags** (verified: `OBS_DIR` is hardcoded to `${REPO_ROOT}/.claude/observability`, `--keep-days` is single-valued, and the script exits 2 outside a git repo) |
| `skills/observability/claude-observability.test.sh` | MODIFY | Test 9 is the existing `clean.sh` test (it `git init`s a temp repo); it gains skill-usage coverage plus the flag-absent bit-identical assertion |
| `scripts/sync-state-key.sh` | MODIFY | one line in `copies=` — a new `lib/state-key.sh` carrier is unmaintained by the sync gate without it |
| `docs/conventions/plugin-data-report-keying/README.md` | MODIFY | adoption table — the Brief cites this table's contents as evidence; no CI gate, so it drifts silently |
| `skills/observability/SKILL.md` | MODIFY | retention table (1 of 4 locations) |
| `skills/observability/context/read-routing.md` | MODIFY | retention table + the skill-reach routing row |
| `skills/observability/context/operator-setup-retention.md` | MODIFY | retention table |
| `.claude-plugin/plugin.json` | MODIFY | MINOR version bump; `"Ten skills"` → `"Eleven skills"` plus an enumeration clause |
| `README.md` | MODIFY | intro count ten → eleven; one `## Skills` row. **Never hand-edit the generated options block** |
| `CHANGELOG.md` | MODIFY | entry per precedent |
| `docs/CATALOG.md` | REGENERATE | `node scripts/generate-catalog.mjs` |
| `docs/SKILL-CHEAT-SHEET.md` | REGENERATE | `node scripts/generate-cheatsheet.mjs` |
| `skills/audit-skill-starvation/evals/evals.json` | KEEP | created in Phase 1 — CI FAILs any `SKILL.md` diff without it, so it cannot wait until here |
| `.claude-plugin/marketplace.json` | KEEP | its entry carries no skill enumeration — precedent `4a1184cd` did not touch it |
| `docs/CATALOG-TAXONOMY.md` | KEEP | governs plugin categories, not skills; `claude-ops` is already `claude-code` |
| `scripts/skill-leaf-name-registry.txt` | KEEP unless colliding | registering a non-colliding leaf is itself a CI failure |

- **Sanity Check:** `bash scripts/validate-plugins.sh` exits 0 — the umbrella already runs the
  catalog and cheat-sheet `--check` pair, `validate-plugin-contracts.mjs`, and
  `generate-identity-prerequisites.mjs --check`, so call it rather than the piecemeal list. Plus:
  `bash scripts/check-skill-leaf-names.sh --check` exits 0 (verified: the script exists and takes
  `--check`, and registering a non-colliding leaf is itself a failure, so
  `skill-leaf-name-registry.txt` stays untouched); `python3 scripts/check-manifest-duplicate-keys.py`
  exits 0; `python3 scripts/sync-plugin-options-docs.py --check` exits 0;
  `bash scripts/sync-state-key.sh --check` and `bash scripts/check-cross-plugin-source-drift.sh
  --check` exit 0 (the new carrier); `grep -c "Eleven skills"
  plugins/claude-ops/.claude-plugin/plugin.json` equals 1; and — in a fixture that **is a git repo**
  (or sets `CLAUDE_PROJECT_DIR`, since `clean.sh` exits 2 otherwise, exactly as Test 9 already
  arranges) — `clean.sh --dry-run --skill-usage-scope user` reports a skill-usage target, proving
  the silent-no-op defect is fixed, while a run with no skill-usage flag leaves hook-events output
  byte-identical to today.

## Blast radius

**MEDIUM-HIGH.** A new module plus a change to a *shared* harness (`clean.sh`) that other skills'
retention depends on, plus generated catalog surfaces gated in CI. Mitigating: the skill is
read-only, adds no hooks, and the only mutation anywhere in the change is one added pruning target.

## Open questions

- **Q18 (USER-RESERVED) — session transcripts in V1? RESOLVED 2026-08-18: NO.** Surfaced at the
  approval gate with the plan-time context it was reserved for; the user approved the plan as
  presented, and no phase reads transcripts. V1 therefore stays machine-local and scope-limited, and
  the Brief's documented cloud/ephemeral gap stands. Revisit trigger: if the scope-limited framing
  proves too narrow in use, transcripts are the known path to retroactive and cross-repo coverage —
  a follow-up topic, not a mid-flight scope change.
- **Q19 — leaf name** `audit-skill-starvation`: confirm via `scripts/check-skill-leaf-names.sh` in
  Phase 7. It collides with nothing today, so the registry stays untouched (registering a
  non-colliding leaf is itself a CI failure).
- **Branch-name note:** the plan is `feat/`-shaped, but this session is mandated to develop on
  `claude/skills-discovery-plugin-z1ij9y`. Keeping it deliberately — the mandate outranks the naming
  convention, and renaming would push to a branch this session is not authorized to use.

## Plan approval

Approved 2026-08-18 after the fresh-context plan review and the applied-findings revision.
Execution shape: **fully sequential** — Phase 1 gates the rest; each later phase consumes the prior
phase's model. Single-session, main-thread execution; no parallel agents (the one file-disjoint lane,
registration, is well under the ~100 LOC threshold that would justify the orchestration cost).
