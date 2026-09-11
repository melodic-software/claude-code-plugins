---
description: "Audit whether each installed skill is actually VISIBLE to the model, and diagnose why most of a fleet never gets used. A skill is invisible when the skill-listing context budget drops its description (Claude Code drops by a decay-weighted usage score, so an unused skill loses its matchable keywords and stays unused), when frontmatter is malformed or a description is missing, when a disabled plugin hides it, or when disable-model-invocation keeps it out of context by design. Reports reachability, observed usage, and whether it is losing the budget contest, computing overflow from documented settings and withholding any verdict the data cannot support. Read-only; never disables, deletes, or edits a skill. Use when: 'why do I never use most of my skills', 'why does Claude never suggest this skill', 'are my skill descriptions being dropped', 'is my skill listing over budget', 'which skills can the model actually see', 'which skills are starved', 'I have too many skills to know when to use them', 'audit skill visibility'. Not for: which skills are unused versus their context cost as a one-shot check (when the built-in /skill-doctor command resolves in your session, prefer it; likewise the bundled /doctor skill when that resolves in your session), repo-authoring listing-budget lint (use skill-quality's check-listing-budget), enumerating what is installed (use /claude-ops:inventory), or reading telemetry infrastructure (use /claude-ops:observability)."
argument-hint: "[--installed [dir]] [--plugins-root <dir>] [--context-window <tokens>] [--bytes-per-token 3|4] [--budget-fraction <f>] [--max-desc-chars <n>] [--render markdown|json] [--now <RFC3339>] [--fixture <path>]. Collects live; --installed reads the plugin manifest, else fleet defaults to ./plugins; unpinned, the budget is a band over both windows and both byte estimates"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: operator
  summary: Which skills the model can actually see, which are starved, and which are unobservable
  cadence: weekly
---

## Purpose

Answers one question: **can the model actually see each of my skills, and if not, why?**

That is the question behind the one operators usually ask, which is *why does most of
my skill fleet never get used?* A skill the model cannot see cannot be chosen, so
"unused" is very often a visibility failure wearing a preference costume.

**Visibility is Claude Code's own term** for this; the settings page documents
`skillOverrides` under "Override skill visibility". This skill audits every way a
plugin skill loses it, and `skillOverrides` is not one of those ways: plugin skills
are governed by `enabledPlugins`, and a plugin resolved to `false` hides every skill
it ships. `skillOverrides` governs non-plugin skills, which this audit does not
enumerate, so it is never cited here as a cause. Verified 2026-09-11 against
<https://code.claude.com/docs/en/skills> ("Plugin skills are not affected by
`skillOverrides`") and Claude Code 2.1.263, whose listing resolver returns `on`
for every plugin-sourced skill before it reads the override map; recheck when
that section changes.

Claude Code budgets the model-visible skill listing in characters, at
`window x bytes-per-token x skillListingBudgetFraction` (default 0.01), and,
when it overflows, **sheds descriptions from the lowest-scoring skills first**.
Names always survive, descriptions do not. A skill at zero usage scores zero, so
it loses its description, loses the keywords a request would match against, and
stays at zero. Unused is partly self-causing.

The window and the bytes-per-token are both per model, so the budget is not one
number for a machine: the same 1% fraction is 8,000 characters at a 200k window
and 40,000 at 1M. This skill never resolves the session's model from disk. It
reads the fraction and the per-entry cap from the settings scopes the product
merges and, unless you pin the model-side inputs, reports the budget as a band
over both windows and both byte estimates, naming no row as this session's.

The budget fraction and per-entry cap are owned by
<https://code.claude.com/docs/en/settings> (`skillListingBudgetFraction`,
`skillListingMaxDescChars`); that page is authoritative and matches. **The drop
ORDER is not.** <https://code.claude.com/docs/en/skills> ("Skill descriptions are
cut short") says "starting with the skills you invoke least", still as of
2026-09-11; the binary ranks by a decay-weighted score and then walks the list
first-fit, so neither the ordering nor the guarantee holds. Take the ordering
from the binary: [reference/listing-scorer.md](reference/listing-scorer.md)
carries the counterexamples, the greps, the budget arithmetic, and the stamp.

So the useful question is not *which skills are unused*. Claude Code already
reports that: the built-in `/skill-doctor` command when it resolves in your
session, and the bundled `/doctor` skill's checkup when that one does, each
behind its own gate, with the Stats tab carrying the `/skill-doctor` report in
an interactive session. It is **which skills are starved by
that loop and still wanted, versus genuinely unwanted, versus not observable at
all.**

## The refusal that defines this skill

A usage store younger than the window being asked about **cannot** distinguish
"never invoked" from "never observed". Reporting the second as the first libels
most of a fleet on any fresh install. A days-old install measured against
30-day and 90-day tiers puts nearly the whole fleet in a "never used" bucket.

This skill therefore computes an `observed_horizon`, clamps every window to it,
and routes any claim the span cannot support into a first-class `withheld`
section with its reason. **A declined verdict is reported, never omitted.**

## Run it

It collects live by default. No fixture required. Two inputs resolve
differently, and the difference decides which command you want:

- **Usage** comes from this machine regardless of where you run it
  (`~/.claude.json`, overridable with `--claude-json`).
- **The fleet being audited**, the denominator, is a plugins directory
  enumerated from disk, and it defaults to **`./plugins` relative to your
  current directory**, not to an installed root.

So from a plugins-layout repo (this marketplace, or any checkout with a
`plugins/` directory), bare audits the tree you are standing in:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-skill-visibility/scripts/audit_skill_visibility.py"
```

Anywhere else that exits non-zero with `no skills found`. Nothing is silently
audited. Name the fleet you mean:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-skill-visibility/scripts/audit_skill_visibility.py" \
  --plugins-root <dir>
```

`<dir>` is any directory holding one subdirectory per plugin, each with a
`skills/` directory, the layout both a marketplace checkout and an installed
plugin root use.

### Auditing the INSTALLED fleet

`--plugins-root` measures a directory. To measure what is actually installed
instead, read the plugin manifest:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-skill-visibility/scripts/audit_skill_visibility.py" \
  --installed
```

It reads `~/.claude/plugins` by default (pass a directory to `--installed` to
point elsewhere). The two answers differ on purpose: a checkout can hold
plugins that are not installed, so the repo count and the installed count
disagree. Neither number is wrong; they answer different questions.

**The manifest lists one entry per install SCOPE, not per plugin.** A
marketplace installed at both `project` and `user` scope carries two entries
per plugin. This resolves to one entry per plugin, and the report states both
numbers so the collapse is auditable. Counting entries would inflate the fleet
and, since the fleet is the denominator, roughly double the reported overflow.

Where a plugin is installed at more than one scope, resolution follows the
documented precedence **`local > project > user`**, the record that loads is
the highest-precedence *applicable* one, **never the newest version installed**.
That rule and its "not the newest" warning are stated in this plugin's own
[`skills/plugins/context/scope-semantics.md`](../plugins/context/scope-semantics.md),
which verified it against the official plugins-reference docs. Getting it wrong
is not cosmetic: plugins pinned at different versions across scopes can ship
different skill *sets* and different `description` text. Superseded records are
listed under **Fleet resolution** so a pin being outranked is visible.

Applicability matters as much as precedence: `project` and `local` records load
**only** in the `projectPath` they name, so another project's records are
excluded and reported rather than counted. Current project comes from
`CLAUDE_PROJECT_DIR`, falling back to the working directory.

A marketplace whose source is a local `directory` loads from that **checkout**,
not from either cached `installPath`. Verified by a skill executing out of the
marketplace directory. For those, the plugin's root comes from the catalog's
declared `source`, since `plugins/<name>` is the common layout but not a rule.

Whether each resolved plugin actually loads is read from `enabledPlugins` in the
same settings scopes the listing budget reads, merged per `plugin@marketplace`
key with the product's precedence: user < project < local < the `--settings`
flag (unread from outside the session) < managed policy. A key set to `false`
makes every skill of that plugin `hidden`, with the scope file that supplied
the `false` as evidence. A key absent from every scope falls back to
`defaultEnabled`, which the plugins reference names as the fallback when
nothing else has decided the plugin's state: first the marketplace entry's
value, read from the marketplace's own `.claude-plugin/marketplace.json`
(evidence `default: marketplace entry defaultEnabled`), then the plugin's
own `.claude-plugin/plugin.json` field (evidence `default: plugin.json
defaultEnabled`), and only with neither present the product's default,
enabled (evidence `default`). A non-Boolean `defaultEnabled` is skipped and
named in the evidence. A scope file that exists but cannot be read or parsed could
have set any key at its own precedence, so plugins whose answer would come
from below it read `unknown`, with that file named in the remedy. Only
`--installed` assesses this: a checkout is not an install, so a
`--plugins-root` run reports reachability as `not-assessed` once for the run.

`--render json` swaps the Markdown report for the machine-readable model, and
`--now <RFC3339>` pins the clock the horizon is measured against.

### The listing budget's inputs

The budget has five inputs, and the report states where each one came from:

- `skillListingBudgetFraction` and `skillListingMaxDescChars` are read from the
  settings scopes with the precedence the product uses, per key:
  user (`~/.claude/settings.json`, relocated by `CLAUDE_CONFIG_DIR`) <
  project (`<project>/.claude/settings.json`) <
  local (`<project>/.claude/settings.local.json`) < the `--settings` flag <
  managed policy. The project is `CLAUDE_PROJECT_DIR`, falling back to the
  working directory. The flag scope lives inside the session and cannot be read
  from outside it, so it is reported as **unread**, never as absent. Managed
  locations (the base file plus the `managed-settings.d` drop-ins, per OS) come
  from this plugin's vendored `lib/managed-scope.sh`, never from a path written
  in the script; when that enumeration cannot run, the policy scope is reported
  as unreadable rather than empty. `--budget-fraction` and `--max-desc-chars`
  pin either value over every scope.
- `SLASH_COMMAND_TOOL_CHAR_BUDGET` overrides the whole computation
  unconditionally, exactly as the product does, and the row then carries
  `budget_basis: env-override`.
- The context window is per model. `CLAUDE_CODE_DISABLE_1M_CONTEXT` collapses
  it to 200k, and `CLAUDE_CODE_MAX_CONTEXT_TOKENS` names it when
  `DISABLE_COMPACT` is also set; both are read from the process environment and
  recorded. Otherwise `--context-window <tokens>` pins it, and unpinned the
  report carries both 200k and 1M.
- Bytes per token is 4 or 3 per model. `--bytes-per-token` pins it; unpinned the
  report carries both.

With nothing pinned the `listing` section is a **band** of four labelled rows
(200k/4, 200k/3, 1M/4, 1M/3), each with its own budget, overflow, verdict, and
starved count, and the top-level numbers are null under `budget_basis: band`.
Pinning both model-side inputs yields the single-row shape with the pinned
numbers at the top level. A row's `budget_basis` names the settings file that
supplied the fraction (`settings:<path>`), `fraction` for the documented
default, or the pin. `inputs` in the JSON, and the "Inputs consulted" list in
the Markdown, carry every scope and variable consulted with its status.

`--fixture <bundle.json>` reads a recorded collection instead of the live one, the reproduction path, used by the tests and for handing someone else's state to
the same engine. It is not needed to get a report.

Python 3.11+ is the only requirement. No third-party packages, matching
`inventory.py` and `install_state.py`.

### The skill-usage store the hooks write

The hooks write `skill-usage.jsonl` where the `skill_usage_scope` and `skill_usage_dir` options
say. Neither script here guesses that location: `audit_skill_visibility.py` takes it as
`--skill-usage`, and `scripts/skill-pair-cooccurrence.sh` resolves it through the resolver the
hooks themselves call. Hand it the rendered option values (a skill subprocess inherits no
`CLAUDE_PLUGIN_OPTION_*` mirror), resolve once, pass the one path to both:

```bash
STORE="$(bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-skill-visibility/scripts/skill-pair-cooccurrence.sh" \
  --scope "${user_config.skill_usage_scope}" --dir "${user_config.skill_usage_dir}" \
  --data-root "${CLAUDE_PLUGIN_DATA}" --print-store)"
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-skill-visibility/scripts/audit_skill_visibility.py" \
  --skill-usage "$STORE"
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-skill-visibility/scripts/skill-pair-cooccurrence.sh" \
  --store "$STORE" --pair <caller>,<callee>
```

An empty or unrendered option value reads as its default, as it does in the hooks. `--data-root`
is the `data-dir` scope's answer and the other two scopes ignore it, so the one call above serves
all three. It is written out here rather than read from the environment because the script takes
no `CLAUDE_PLUGIN_DATA` fallback: a skill subprocess can carry another plugin's value, and the
Bash tool does not inherit this one at all, so the skill body's own expansion is the only
trustworthy source. Flags, that reason, and missing-store behavior:
[reference/pair-cooccurrence.md](reference/pair-cooccurrence.md).

## Reading the output

Three independent fields per skill; a single flat verdict would collapse
questions that demand different actions.

| Field | Answers | Phase |
|---|---|---|
| `observation` | What has actually been seen, within a stated horizon | **live** |
| `reachability` | Can the model ever select this skill | **live** |
| `starvation` | Is it competing for description budget, and likely losing | **live** |

`observation` values: `active` · `cooling` · `dormant` · `no-observation-in-horizon`
· `not-observable`. The last is the default whenever the data cannot support
better, and it is never a synonym for unused.

`reachability` values: `model-reachable` · `user-only` · `hidden` ·
`misconfigured` · `unknown` · `not-assessed`. Only `model-reachable` with no
observation is a starvation candidate. `user-only` means you type it by design,
`hidden` means the owning plugin resolves to disabled, through an
`enabledPlugins` entry or through `defaultEnabled` when no scope names it, and
`misconfigured` is a fix. `unknown` is reserved for a settings file the reader
could not parse, and `not-assessed` is the checkout-mode answer, where there is
no install to read enablement from. Each carries its causes, evidence, and a
remedy.

**The reachability causes are not an official list.** No such list is published;
this catalogue is assembled from scattered documentation plus strings in the
shipped binary, and every row says so in its `provenance`. Do not present it to
a user as documented.

`starvation.verdict` values: `likely-starved` · `likely-retained` ·
`listing-fits` · `withheld` · `not-assessable`. A listing that overflows with no
usage recorded for any competing skill reports `withheld` with
`reason: "unscored"` on every competing row and no band, because at all-zero
scores the product's ordering is the catalog-order tie its stable sort leaves,
and naming rows would sell catalog position as preference. How many descriptions
cannot fit is arithmetic and is still reported, as `starved_count` and as a
count in the Markdown; the run carries one run-level `withheld` entry for the
per-skill claim, never one per skill.

`not-assessable` marks the rows that never enter the contest, with
`starvation.eligibility` naming why: `exempt-bundled` (a bundled skill keeps
its description unconditionally), `exempt-user-only` (`disable-model-invocation`
keeps it out of context), and `exempt-hidden` (the owning plugin resolves to
disabled, so the product never loads the skill). Exempt rows contribute no
`demand_chars`, so a fleet whose only excess sits in disabled plugins reports
`listing-fits`. Only a settled disabled plugin exempts: a `not-assessed`
checkout row or an `unknown` one keeps competing, because unknown is not hidden.

The Markdown names what these fields hold rather than only counting it. Under
Reachability, hidden plugins are tabled with the scope file that disabled them,
and misconfigured skills with their cause and one remedy per cause. Under
Listing budget, when any row overflows, the ten longest competing descriptions
are tabled by source length beside the capped charge the listing counts
(`description_chars` and `demand_chars` in the JSON): trimming lowers the
overflow only once a description is under `skillListingMaxDescChars`, and the
table is labelled as length, never as a starvation ranking, so it renders the
same in an unscored run. Each table caps at ten rows and counts the rest. A
closing Next actions section names only the fixes this run's findings support,
points at the budget control the run's provenance says is effective (the env
override when set, the managed policy when it supplied the fraction, otherwise
the settings file that did), and says so when there is nothing to fix.

## Counting rules that are not obvious

- **Never sum sources.** Native counters and the JSONL store both record the
  same invocation, so adding them double-counts. At a given instant the count is
  the MAX across sources, while two events from ONE source at the same instant
  still count twice, because those are genuinely two invocations.
- **`pluginUsage` is not a skill signal.** It counts hook, agent, MCP, and LSP
  dispatch, and is seeded at install with `usageCount: 0` beside a current
  `lastUsedAt`. Recency from it is meaningless unless `usageCount > 0`.
- **Ambiguous attribution is reported, not guessed.** Two marketplaces shipping
  a same-named plugin collapse to one usage key; those rows are marked
  `ambiguous-attribution` rather than attributed to one of them.
- **Two possible usage keys per skill.** The stores hold the qualified
  `<plugin>:<leaf>` key and the bare leaf as separate rows. Both are collected; a
  bare key is attributed only when exactly one skill owns that leaf, ambiguous
  ones are withheld with their candidates.
- **The starvation band is decay-weighted, not a count**, and reports
  `score_basis: "unscored"` when nothing survives to weigh. Read
  [reference/listing-scorer.md](reference/listing-scorer.md) before changing that
  ordering or quoting it to a user.

## Scope boundary

| Question | Owner |
|---|---|
| Why is my fleet unused, starved, unwanted, or unobserved? Does skill B get invoked where skill A ran? | **this skill**, the second via `scripts/skill-pair-cooccurrence.sh`, co-occurrence and never attribution ([reference/pair-cooccurrence.md](reference/pair-cooccurrence.md)) |
| Which skills are unused vs their context cost, right now? | Claude Code's own built-in `/skill-doctor` command, when it resolves in your session; the bundled `/doctor` skill's checkup, when that one resolves; the Stats tab carries the `/skill-doctor` report in an interactive session |
| Is a repo's authored listing over budget? | `skill-quality`'s `check-listing-budget.sh` |
| What is installed and invocable? | `/claude-ops:inventory` |
| Is the telemetry pipeline healthy? | `/claude-ops:observability` |

Read-only. It never disables, deletes, or edits a skill, and it never
recommends deleting one it classified as misconfigured. That class is a
fix-me, not a removal candidate.

## Boundary, the bundled `doctor` skill and `/skill-doctor`

Two native Claude Code surfaces answer the question this skill starts from, and the three get
conflated whenever a fleet looks unused:

- **`doctor` (bundled skill, alias `/checkup`).** Ships with Claude Code rather than as a
  marketplace plugin. Among its checks it finds unused skills, MCP servers, and plugins against
  their context cost, groups them with a benefit estimate, and offers to disable the groups the
  user selects. It reports first and asks before changing anything.
- **`/skill-doctor` (built-in command).** Shows which loaded skills go unused and what they cost in
  context; the Stats tab carries its report in an interactive session.
- **This skill (marketplace plugin).** Reconciles the native counters with a JSONL store and OTEL,
  computes an observed horizon, and separates starved-and-wanted from unwanted from unobservable,
  withholding every verdict the span cannot support. Read-only.

**Routing.** When either native surface resolves in your session, prefer it for "which skills are
unused versus their cost, right now". Prefer this skill when the answer has to survive a young
usage store, when starved and unwanted must be told apart, or when the question is whether skill
B fires where skill A ran.

**Mutation gate.** `doctor` disables. This skill never disables, deletes, or edits a skill, so
never chain into a `doctor` disable on this skill's behalf; report the classification and let the
user act.

**Availability is never assumed.** `doctor` survives the bundled-skill kill switch but an
environment variable or a `skillOverrides` entry still hides it, and `/skill-doctor` has its own
gate; this section states what to do when one resolves, never that it is present. The four-part
records live in [reference/bundled-doctor.md](reference/bundled-doctor.md).

## Gotchas

- **A short horizon is the normal case, not an error.** Fresh installs, new
  machines, and ephemeral cloud containers all produce spans below the exposure
  floor. The correct output there is a withheld verdict, not a smaller number:
  if a run reports most of the fleet as cold on a days-old install, the report is
  wrong, not the fleet.
- **Do not "fix" a fixture that asserts everything is `not-observable`.** That is
  the honesty floor being tested, and it is the defect this skill exists to
  prevent.
- **Never sum two sources.** Native counters and the JSONL store record the same
  invocation; summing them doubles every count. The reconciliation is MAX across
  sources at an instant, and it is deliberately not MAX across an entire skill:
  two same-instant events from one source are two invocations.
- **OTEL and native counts legitimately disagree.** The native counter is
  debounced (one write per skill per 60 s, suppressing the timestamp refresh
  too); telemetry is not. Divergence is expected and must not be reconciled away.
- **`misconfigured` never renders as a removal candidate.** Several of its causes
  are silent misconfigurations, a skill that looks fine and can never be
  selected. The remedy is a fix.
