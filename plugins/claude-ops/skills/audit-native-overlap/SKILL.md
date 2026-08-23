---
description: "Map native Claude Code surfaces, built-in CLI commands, bundled skills, plugin-backed built-ins, session-provided skills, against the current repo's plugin skills and agents, so a custom component never silently duplicates what Claude Code itself now ships. Bare invocation is a READ-ONLY report: overlap candidates with evidence, the detection integrity floors carried through, and a listing-budget exposure section. Verdicts (prefer-native, prefer-ours, complementary, superseded, defer) are human-gated and recorded in a committed store rendered into a generated registry; only an explicit `apply` argument edits a component, baking presence-gated native references into descriptions and Boundary sections. Use when: 'does this skill duplicate a built-in', 'what does Claude Code already ship for this', 'audit native overlap', 'is our install-state audit the same as /doctor', 'refresh the native-surfaces registry', 'bake the native reference into this skill', 'which of our skills overlap bundled skills'. Not for: enumerating what this machine can invoke (use /claude-ops:inventory), MCP tool overlap (use /mcp-tools:audit), plugin fleet currency (use /claude-ops:plugins), or ingesting a CLI release (use /claude-ops:changelog)."
argument-hint: "[report|apply <plugin>] [--store <path>] [--inventory <path>]. Bare runs the read-only report"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Map native Claude Code surfaces against this repo's components and record human-gated verdicts
  cadence: weekly
---

## Purpose

Answers one question: **which of this repository's components now overlap something Claude Code
ships itself, and what should each one do about it?**

Claude Code's own surface moves every week. A skill written when no bundled equivalent existed can
wake up duplicating one, and nothing in the product says so. Plugin skills are namespaced, so a
native surface never shadows ours and the collision is silent. The model then picks between two
overlapping capabilities from descriptions alone.

This skill makes the overlap visible, records a human verdict per pair in a committed store, and, only when asked, bakes the resulting routing guidance into the components themselves.

Three things it is not: it is not an availability oracle (nothing here asserts a native surface is
present in anyone's session), it is not a verdict engine (every verdict is a human's), and it is
not a fleet editor (bare invocation mutates nothing at all).

## Scope boundary

| Question | Owner |
|---|---|
| Which of our components overlap a native surface, and what should they say about it? | **this skill** |
| What can this machine actually invoke, and where did each thing come from? | `/claude-ops:inventory` |
| Is this machine's install directory healthy? | `/claude-ops:audit-install-state` |
| Is the plugin fleet current, and at what scope? | `/claude-ops:plugins audit` |
| What changed in the last CLI release? | `/claude-ops:changelog` |
| Do our MCP tools duplicate each other or the built-ins? | `/mcp-tools:audit` |
| Is this SKILL.md structurally sound, and is the listing over budget? | `/skill-quality:check` |
| Is each installed skill actually VISIBLE to the model right now, and why not? | `/claude-ops:audit-skill-visibility` |

The line that matters most: `inventory` enumerates **what resolves**; this skill compares that
surface against **what we ship** and produces a routing verdict. Inventory never judges; this skill
never enumerates for its own sake.

## The two substrates, named

Detection has exactly two inputs, and they are not interchangeable.

**Native side, an inventory JSON.** Produced by the sibling extractor in this same plugin:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py" \
  --binary-only --out ./claude-inventory.json
```

The consumer asserts `schema == 1` and presence-checks every key it reads. `builtin_commands`,
`bundled_skills`, `plugin_backed`, `integrity`. A missing key is reported as **broken**
consumer-side, not worked around: the extractor's integrity block guards extraction-level drift,
not the emitter's own top-level key names, so a renamed key would otherwise read as an empty
surface.

**Target side. This skill's own repo-tree scan.** `plugins/*/skills/*/SKILL.md` and
`plugins/*/agents/*.md` frontmatter, in the repository being audited. The extractor scans
*installed* trees, which are not necessarily the audited repo's. Using it for the target side
would silently audit the wrong fleet.

Seeded candidate pairs live beside this skill in `reference/canonical-pairs.json`. They are
candidates, never verdicts: a pair there proposes a row for a human to rule on.

## Run it

The engine is `scripts/overlap.py`. Python 3.11+, standard library only, three subcommands:

```bash
# Candidates: merge the extraction, the repo tree, and the seeded pairs.
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-native-overlap/scripts/overlap.py" detect \
  --inventory ./claude-inventory.json --out ./overlap-candidates.json

# Registry: render the store into the generated view (--check diffs instead).
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-native-overlap/scripts/overlap.py" generate

# Freshness: the deterministic gate.
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-native-overlap/scripts/overlap.py" self-check
```

`--repo`, `--store`, `--view`, and `--pairs` are flags with repo-relative defaults, so a consumer
repository with a different layout points them wherever its files live.

Every subcommand exits `0` ok, `1` broken, `3` degraded, the sibling extractor's contract, not the
shell gates' `0/1/2`, so one lane can carry both; `2` stays argparse's usage error. A degraded exit
is a passing run: it means the data is stale-but-honest or something was not locally decidable, and
the run says which. The suite is `scripts/test_overlap.py`, wrapped by `scripts/overlap.test.sh`
for the repo's test discovery.

## Detection posture. Floor-honest

Under-recall stated honestly beats confident completeness. Three rules:

- **Carry the integrity floor through.** If the inventory reports `degraded`, every native-side
  count in the report is a floor and the report says so in the same sentence as the number. If it
  reports `broken`, the report carries no native-side counts at all.
- **Never auto-verdict.** Detection emits candidates with evidence. The verdict column is empty
  until a human fills it.
- **Accept human-added candidates.** A pair nobody's heuristic found is a first-class row; add it
  to the store directly, or to the seeded pairs file when it generalizes.

## Report structure (bare invocation)

```
# Native overlap — <repo>, <date>

## Detection integrity
Inventory status (ok | degraded | broken), cli_version vs validated_against, and what that
means for every count below.

## Overlap candidates
One row per (native surface, our component): native name + provenance class + hidden/gated
markers, our component, the evidence, and the store's current verdict — or NEW where the
store has no row yet.

## Registry state
Rows whose recheck trigger has fired, rows missing a baked line, rows baked but unverified.

## Budget exposure
What baking would cost the shared skill-listing budget, and which rows are already exposed
to name-only degradation.

## Provenance
Which substrate produced which section, and anything the run could not resolve.
```

Provenance classes are never merged into one list. A bundled skill, a built-in command, a
plugin-backed built-in, and a session-provided skill have different disable switches and different
rosters per host; a merged list cannot be acted on.

## Budget exposure, a presence-gated seam

Baked phrases live in frontmatter descriptions, which are the routing-effective surface:
descriptions load into model context by default, while bodies load only on invocation. That surface
is budgeted twice over, the combined `description` + `when_to_use` text truncates at 1,536
characters per entry by default, and the listing as a whole is capped at a share of the context
window (1% by default), on overflow keeping every skill *name* and dropping whole descriptions
starting with the least-invoked skills.

So the report says what the baking would cost. When the `skill-quality` plugin is installed, invoke
`/skill-quality:check listing-budget` over the repo's plugin skill roots and fold its aggregate
estimate into the Budget exposure section. When that plugin is not installed, state "budget
exposure unavailable. `skill-quality` not installed" and continue; never reach into another
plugin's files by path to fake the number.

A fleet already over budget does not make baking pointless. It makes a baked phrase the best
available surface rather than a guaranteed one. Rows in that state carry the store's
`budget_caveat` flag so no later reader mistakes a baked phrase for a guarantee the model saw it.

## Verdicts and the human gate

Five values, no blanket preference rule:

| Verdict | Means |
|---|---|
| `prefer-native` | The native surface does this job at least as well; ours should route to it |
| `prefer-ours` | Ours is materially better for this job. **A reason is required**, not optional |
| `complementary` | Different jobs that look alike; both keep their lane and each names the other |
| `superseded` | The native surface fully absorbed ours; ours is a retirement candidate |
| `defer` | Undetermined. Gated, experimental, or unverifiable from this session's evidence |

<!-- fresh-eyes-exempt: external-input -- recommendations are judgments about components and native surfaces this context did not produce; the binding verdict is the human reviewer's, recorded in the store, never this run's -->
A run may **recommend** a verdict with its reasoning; it never records one. The recommendation goes
into the report labelled as a recommendation, and a human writes the store row. No component file
is touched before a verdict exists in the store.

Session-provided (cloud) surfaces are observation-only: they are absent from any binary extraction,
so their rows carry a live-roster observation, a `defer` verdict, and no baked line, until an
in-session capture protocol exists, a cloud row's evidence is one environment's roster on one day.

## The store, the view, and the self-check

Three artifacts, one direction of flow:

1. **The store**, a committed, hand-editable JSON file (default `docs/native-surfaces/records.json`
   in this repository; configurable). It is the SSOT. Every row carries: the native surface with its
   provenance class and hidden/gated markers, our component, the verdict and its reason, evidence, a
   class-tagged observation record, a recheck trigger with its verified date, `baked` flags, and the
   budget caveat.
2. **The generated view**. `docs/NATIVE-SURFACES.md`, rendered from the store between HTML
   markers, per provenance lane. Never hand-edited; a `--check` mode regenerates and diffs.
3. **The self-check**, a deterministic script over what is locally decidable: store parses and
   declares its schema, every row carries a trigger, records are well-formed including their
   observation class tags, the view matches the store, every baked line traces back to a store row,
   and the store's recorded CLI version still matches what the environment reports.

**Observation records name their evidence class.** *Extraction-evidence* reads "extracted from
binary v&lt;X&gt; on &lt;date&gt;"; *live-roster observation* reads "observed in &lt;env&gt; session
on &lt;date&gt;". Neither is ever flattened into "this surface is available". See
`docs/conventions/native-references/README.md` for why any static availability claim is wrong
somewhere by construction.

**A recheck trigger names an observable event.** "A Claude Code release adds, removes, or renames a
bundled skill in this row's lane" qualifies; a bare date does not. That bar is the upstream-drift
convention's, and this skill's self-check enforces trigger *presence* only. Deciding whether an
event actually fired is a session act performed by the report, because an offline gate cannot
re-fetch an upstream basis.

## The apply step

`apply` is the only action that edits a component, and it edits one plugin at a time.

Preconditions, all required: the store has a row for the pair; the row's verdict is not `defer`;
the row's observation class is extraction-evidence (session-provided rows are never baked); and the
user asked for this plugin by name.

What it emits, per the native-references convention:

- **A description phrase**. One clause, front-loaded, carrying the presence gate ("when the
  bundled &lt;name&gt; skill resolves in your session, prefer it for …; this skill for …"), the
  provenance class, and the routing split. It must fit inside the per-entry cap with the existing
  description, and it cites nothing outside its own plugin, a shipped plugin has no copy of this
  repository's registry, so a citation would be a broken reference at install time.
- **A Boundary section** in the body where the clause is too small for the real distinction,
  naming each overlapping surface by provenance class with a mutation gate where the surface
  mutates.

Then set the row's `baked` flags and re-run the self-check. Parity is **direction-sensitive**:
every baked line must trace to a store row, while a store row with no baked line is legal
pending-sweep state.

Agents are registry-rows-only. An agent's role prompt loads after dispatch, so a routing line there
reaches the model too late to change the routing; the actionable line belongs at the dispatching
skill's surface.

## The sweep execution contract

Applying across the fleet is a sweep, and a sweep is executed as a sequence of closed units. Never
as one fleet-wide edit.

**One plugin is one unit.** For each unit, in order:

1. **Apply**. Bake the description phrases and Boundary sections for that plugin's rows only.
2. **Verify**, the overlap self-check passes; `/skill-quality:check` passes for every touched
   skill; the plugin version takes its bump; the plugin's CHANGELOG carries the entry.
3. **PR**. Open one PR for that unit, with the affected store rows quoted in the body so a
   reviewer gates the routing change on the same evidence the verdict rested on.
4. **Close**, the unit is closed **only when its PR merges green**. A merged-but-red or an open PR
   leaves the unit open, and the next unit does not start.

Two units are never in flight at once: description edits are routing-affecting, and a half-applied
fleet is a fleet whose routing nobody can reason about. Whether to run the sweep at all is a
separate human go/no-go, not something a run decides for itself.

## Running in a foreign repository

This skill ships to consumers, so it never assumes this marketplace's layout. Store and view paths
are arguments with repo-relative defaults; the target-side scan walks whatever plugin tree it finds.

Where the conventions tree, the store, or the CI gates are absent, the skill **degrades to
report-only**: it detects and reports overlaps, states that no store was found at the resolved
path, and makes the apply machinery unavailable rather than erroring or writing a store into a
repository that never asked for one. Report-only is a working outcome, not a failure.

CI wiring is a property of a repository, not of this skill: a consumer wires the self-check into
whatever gate they run, or runs it by hand.

## Verifying an upstream claim

Any claim about what Claude Code itself ships must come from the raw markdown endpoint. `curl -sSL`
`https://code.claude.com/docs/en/skills.md` to a file, then read the file. A summarizing fetch
returns a small model's answer *about* the page, so absence from that answer is not evidence of
absence. A `200` is also not proof you got the page you asked for: retired slugs are silently
aliased, so confirm the slug against `https://code.claude.com/docs/llms.txt` and read the body's
own first heading before quoting it.

Two upstream facts this skill depends on, each with the trigger that obliges re-deriving it:

| Claim | Basis | Recheck trigger | Verified |
|---|---|---|---|
| Descriptions load into context by default, truncated at 1,536 chars per entry, listing capped at 1% of the context window with name-only degradation least-invoked-first | `docs/en/skills.md` (Frontmatter reference; Troubleshooting), `docs/en/settings-reference.md` | Either default moves, or the drop order changes | 2026-08-23 |
| Native availability varies on settings/env, plan, platform/provider, and host surface, so no static availability claim holds | `docs/en/settings-reference.md`, `docs/en/env-vars.md`, `docs/en/commands.md`, `docs/en/cloud-environments.md` | A release or docs change adds, removes, or renames a gating axis | 2026-08-23 |

## Gotchas

- **A plugin skill never shadows a native one.** Ours are namespaced, so both resolve and the model
  chooses. That is why the routing lives in descriptions rather than in a name.
- **`plugin_backed` is its own lane.** `security-review` is reported there, not under
  `builtin_commands`. Read the wrong key and the row looks absent.
- **A bundled skill can carry aliases.** `code-review` answers to `review`; treating an alias as a
  separate surface produces a duplicate row for one capability.
- **Absent from the binary is not absent from the product.** Session-provided skills exist only in
  a live roster. "Not in the extraction" is a statement about the extraction.
- **A verdict is not permanent.** The trigger is the load-bearing part of the row; a date alone
  tells a later reader nothing about whether the verdict still holds.
- **Baked text is self-contained by contract.** A phrase that says "see the native-surfaces
  registry" ships a broken reference to every consumer who installed the plugin.
