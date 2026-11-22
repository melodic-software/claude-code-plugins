# overengineering: consumer configuration

Owner doc for this plugin's configuration file: `<home>/overengineering.yaml` in the consuming
repository, layered per the consuming marketplace's
[config-cascade layers](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#the-layers).
Every layer is optional. Zero config is a fully working state, and the bundled defaults in
`context/scrutiny-method.md` (§7 protected patterns, §9 thresholds, §11 observation window) apply
verbatim.

The keys are declared here rather than in the plugin's `README.md` because the cascade's boundary
rule puts key ownership in the concern's own owner doc or in the plugin's bundled reference. The
README summarizes and points here.

## Why not `userConfig`

This plugin ships **no `userConfig` block**, deliberately. `userConfig` is a personal, enable-time
surface, and the marketplace's artifact protocol states outright that it "is not a coordination
surface for repository artifacts". Two of the keys below are policy: which mechanisms this plugin
may never recommend retiring on its own, and which findings an operator has already judged. A
protected set silently emptied in one operator's personal options would defeat the FLAG-FOR-HUMAN
cap for everyone reading that operator's report, with no diff anywhere to show it happened. A
tracked file in the consuming repo is the reviewable place for a policy change, so that is where
it lives.

Nor is there a user-global file. Every key below is a statement about one repository: which of its
mechanisms may be recommended for retirement, which of its findings were judged, and the
thresholds, window and noise budget its own audit and release cadence call for. A value that
followed one person across repositories would have nothing to attach to, so each key lives in the
team file, and one person's deviation in one repository lives in the personal override.

## Layers and merge semantics

Three layers, lowest first:

| Order | Layer | Path |
|---|---|---|
| 0 | plugin default | the bundled defaults: `context/scrutiny-method.md` and the Default columns below |
| 1 | team (tracked) | `<home>/overengineering.yaml` |
| 2 | personal override (gitignored) | `<home>/overengineering.local.yaml` |

`<home>` is the convention home bound in the pointer region of the consuming repository's
`AGENTS.md` or `CLAUDE.md`, else `docs/conventions`
([config locations](config-locations.md)). Anchor both paths at the git top-level. When that root is
`$HOME` or an ancestor of it, or is not inside a git working tree, the team and personal layers do
not apply, nor do the old repository files below: report them as not applicable and use the bundled
defaults, with the old user-global file applied over them while it exists. Whenever the run surfaces
the effective config, it reports which layer supplied each value, `default` for a bundled one.

**Merge form: per-key override**, declared here as the cascade convention requires. The values are
scalars and closed mappings, where concatenation is meaningless: a later layer replaces an earlier
layer's value key by key, a key absent from a later layer keeps the earlier value, and wholesale
replacement is forbidden.

**Two key groups additionally sit in the cascade's sanctioned policy-floor precedence-inversion
class**: `protected_categories` and `suppressions`. On a direct conflict there the **team layer
wins**, the reverse of the default; a personal layer (the personal override, or an old personal
file the dual-read window below still reads) may extend or tighten only, never weaken; and whenever a personal layer materially shapes output, the
run **names the contributing layer**. The remaining keys, `thresholds`, `observation_window`, and
`delta_noise_budget`, take the ordinary refinement form, where a later layer's value simply wins.

A gitignored personal override that emptied the protected set, or
suppressed a finding the team never accepted, would recreate exactly the hole that disqualified
`userConfig`.
Thresholds, the observation window, and the delta noise budget carry no such hazard: a personal
threshold changes what one operator's own report ranks, and the finding it moves is still reported.

Every file layer absent is a valid state. The bundled defaults apply and the run says so.

## Old paths: the dual-read window

Earlier versions read three other files. While one exists, every skill that resolves this config
still reads it, so no setting in it is dropped:

| Old file | Read as | Until this file exists | Move its settings to |
|---|---|---|---|
| `~/.claude/overengineering.md` | a personal layer, below the team layer | `<home>/overengineering.local.yaml` | `<home>/overengineering.local.yaml`, or the team file for a key the team should share |
| `.claude/overengineering.md` | the team layer | `<home>/overengineering.yaml` | `<home>/overengineering.yaml` |
| `.claude/overengineering.local.md` | the personal layer | `<home>/overengineering.local.yaml` | `<home>/overengineering.local.yaml` |

An old file holds the same keys in a fenced YAML block. Read it as it was read before: the old
user-global file sits below the team layer, and the old personal override above it. Once the new
file in the "Until this file exists" column exists, it supplies that layer and the old file is not
applied.

**Warn on every run, one line per old file.** With only the old file, print
`warning: overengineering still reads <old path>; move its settings to <new path>, then delete <old path>`.
With both, print
`warning: overengineering reads <new path> and ignores <old path>; move any setting only <old path> holds to <new path>, then delete <old path>`.
The old user-global file applies in every repository, so its warning differs: print
`warning: overengineering still reads ~/.claude/overengineering.md; copy its settings to <new path> in each repository that relies on it, then delete it`,
with `reads <new path> and ignores` in place of `still reads` when this repository's personal
override exists. Deleting it after moving it into one repository would drop its settings, with no
warning, everywhere else.
This plugin has no setup skill to make the move, so the warning names the hand move. Moving a
threshold, window or noise-budget key from the old user-global file into the personal override
changes who wins: there it beats the team file's value, where before the team value beat it. Leave
such a key out of the move when the team value should keep winning.

Removing these reads is a later change, made once no run reports an old file.

## File format

Plain YAML, validated by [`schemas/overengineering.schema.json`](../schemas/overengineering.schema.json).
Both new files take this shape:

```yaml
protected_categories:
  audit-trail-retention: off
  release-signing:
    match:
      - "scripts/sign-*"
      - ".github/workflows/publish.yml"

thresholds:
  exercise_frequency_days: 180
  inactivity_window_days: null

observation_window:
  days: 45
  release_cycles: 1

delta_noise_budget:
  new_finding_verdicts:
    - RETIRE
    - CONSOLIDATE
    - FLAG-FOR-HUMAN
  unproven_head: 5
  verdict_change: boundary
  closed_findings: unexpected
  member_verdicts: count
  max_items: 20

suppressions:
  230042849f499636:
    check: overengineering/audit/rule-ci-lanes
    claim: enforcement-item
    sites:
      - surface: .github/workflows/nightly.yml
        "anchor/v1": "0d5658b4"
    reason: "Kept deliberately: the lane is our only pre-release smoke path."
    date: 2026-08-17
```

Every top-level key is optional, and so is the file. Quote the `"anchor/v1"` key: the shared
YAML-subset parser the repository's convention-YAML gate runs accepts a plain key of letters,
digits, `_` and `-` only. Unknown keys are inert per the cascade's
soft-degradation rule.

**The suppression entry above is derived, not illustrative.** Its `anchor/v1` is
`sha256` of the ordered locator path `[".github/workflows/nightly.yml"]` truncated to 8 hex, and its
key is `sha256` over the `US`-joined `[check, claim, surface, anchor]` truncated to 16 hex, the same
rule the plugin enforces on every entry it reads. Anyone editing the example re-derives the anchor
and then the key, in that order: editing an anchor changes the key that hashes it, and an entry whose
constituents no longer hash to its own key is reported as malformed and suppresses nothing. A
hand-written example would therefore be an example nobody can copy.

## Keys

| Key | Type | Class | Meaning |
|---|---|---|---|
| `protected_categories` | mapping | policy-floor | Which categories carry the FLAG-FOR-HUMAN cap (`context/scrutiny-method.md` §7), keyed by category id. |
| `thresholds` | mapping | refinement | Overrides for the analogical threshold rows (§9). |
| `observation_window` | mapping | refinement | The rollback ladder's rung-2 observation window (§11). |
| `delta_noise_budget` | mapping | refinement | What `overengineering:delta` lists rather than counts, per delta class. |
| `suppressions` | mapping | policy-floor | The durable judgment record, keyed by `finding_id`. |

### `protected_categories`

Keyed by category id. The seven bundled ids map **one-to-one onto §7's seven default-pattern
bullets**, in that order: `secrets-and-credentials`, `destructive-operations`, `bypass-guards`,
`access-control`, `supply-chain-integrity`, `security-scanning`, `audit-trail-retention`. Each is
`on` unless a layer says otherwise, and each value is one of:

| Value | Effect |
|---|---|
| `on` | The category applies with the method's bundled patterns. |
| `off` | The category does not apply. **Team layer only** (see below). |
| mapping with `match:` | A list of path globs or kind-prefixed identifiers. On a bundled id the list **adds to** the method's patterns; on an id the method does not define, it declares a consumer category. |

**Extend, narrow, empty, and which layer may do which.** Adding a category, or adding a `match`
pattern to one, is a tightening: any layer may do it, and a personal contribution is named in the
report. Turning a category `off`, or removing a `match` pattern the team layer carries, is a
weakening: **only the team-tracked layer may do it.** A personal layer's `off` is read, reported as
`personal-only, not applied`, and does not take effect. That is the same disposition the
finding-suppression contract gives a personal-only suppression, and for the same reason.

**Emptying the set is spelled one category at a time.** There is deliberately no single
disable-everything token: emptying is seven explicit `off` values in the tracked file, so the review
diff names each protection being dropped rather than hiding all seven behind one word. That is what
makes "consumers can empty the set" a reviewable decision instead of a silent one.

The method's **intentionally-dormant** class and its **absence-of-incident** rule (§7) are not
consumer keys in this version, and are not among the seven ids above. Both are rules about what
inactivity and incident evidence can *mean*, not policies about what may be recommended, so neither
carries a weakening a personal layer could perform.

### `thresholds`

One key per row of the §9 analogical-thresholds table. Every row is a labeled transfer from alerting
and feature-flag literature, so overriding one, or switching it off, is expected, not exceptional.

| Key | Type | Default | §9 row |
|---|---|---|---|
| `accuracy_floor` | number 0–1 | `0.5` | Accuracy floor |
| `false_positive_attention` | number 0–1 | `0.1` | False-positive attention line |
| `exercise_frequency_days` | integer | `90` | Exercise frequency |
| `staleness_age_days` | integer | `30` | Staleness gate, "older than" condition |
| `staleness_unevaluated_days` | integer | `7` | Staleness gate, "not evaluated in" condition |
| `inactivity_window_days` | integer | `56` | Inactivity window |

`null` **disables** a row: the audit stops citing that threshold entirely and falls back to the
qualitative bar §9 names as the safer instrument. A consumer who rejects the analogical transfer
outright sets every row to `null` and loses no other capability.

A configured value does not become a native fact. A finding citing a threshold still carries the
row's source and its analogical label verbatim, whether the number came from this file or from the
bundled default.

### `observation_window`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `days` | integer | `30` | Calendar length of the rollback ladder's rung-2 window. |
| `release_cycles` | integer | `1` | Release cycles the window must also span. |

The effective window is **whichever of the two is longer**, per §11. Setting either to `0` drops that
constraint; setting both to `0` is rejected rather than silently taken, because a window with no end
date is the abandonment §11 exists to prevent.

### `delta_noise_budget`

The noise budget for the recurring lane, `overengineering:delta`. Every key answers one question:
which delta class is **listed** as a row, and which is only **counted**. The class rules themselves,
what a boundary crossing is and what makes a closure unexpected, are owned by that skill's body and are
deliberately not re-derived here; this table owns the keys, their types, and their defaults.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `new_finding_verdicts` | list of verdict tokens (§6), or `all`, or `[]` | `[RETIRE, DOWNGRADE, CONSOLIDATE, FLAG-FOR-HUMAN]` | Which newly-opened findings are listed. Others are counted. `all` lists every new finding; `[]` counts them all. `UNPROVEN` in this list is overridden by `unproven_head`. |
| `unproven_head` | integer ≥ 0 | `3` | How many newly-opened `UNPROVEN` findings are listed, taken off the audit's own carry-cost ranking. `0` counts them all. |
| `verdict_change` | `boundary` \| `any` \| `off` | `boundary` | Which verdict moves on an unjudged (`Status: OPEN`) finding are listed. `off` counts them. Has no effect on a verdict that moved under a carried-forward judgment, which is never configurable. |
| `closed_findings` | `unexpected` \| `all` \| `off` | `unexpected` | Which closures are listed. `off` counts them. |
| `member_verdicts` | `count` \| `surface` \| `off` | `count` | Member-level verdict moves inside a container whose own verdict did not move. `off` omits them entirely. |
| `max_items` | integer ≥ 1 | `20` | Cap on rows listed across every class in one cycle. The residue is reported as counts with a pointer to the artifact. |

**Two delta classes are deliberately absent from this table, and no layer can weaken them.** A
verdict that moved under a **carried-forward judgment** (the artifact's merge rule 5) and a **status
change** are always listed. The first is the one class where a decision a human already made has gone
out of date under new evidence, and a key that could hide it would hide the operator's own concern
from them. The second reports that a human acted, is rare, and costs one row. They are not keys set to a
locked default; they are not keys at all.

**Why refinement and not policy-floor.** The policy-floor class exists for keys whose weakening in a
personal layer would take something away from *everyone else* with no diff to show it: an emptied
`protected_categories` defeats the FLAG-FOR-HUMAN cap for whoever reads that operator's report, and a
personal `suppressions` entry records a judgment the team never made. Neither hazard exists here.
Every key above governs **what one run's delta view lists versus counts**, and nothing it can do
removes a finding from the artifact, changes a verdict, suppresses a judgment, weakens the protected
cap, or authorizes a remediation. The artifact stays complete and remains the source of truth in
every configuration, and a counted item is one line away from being read in full. The two classes
where hiding would actually cost someone something are not configurable at all. A personal
`max_items: 5` changes what one operator's own cycle leads with and nothing else, which is exactly
the test `thresholds` and `observation_window` already pass.

### `suppressions`

The durable judgment record: an operator's accepted-keep or REJECTED judgment, persisted so it
survives the branch switches, removed worktrees, and reclaimed containers that lose the memory-tier
findings artifact.

**The entry format is the marketplace's finding-suppression contract, not this plugin's.** A mapping
keyed by `finding_id`, each entry carrying all five required keys, `check`, `claim`, `sites`,
`reason`, and `date`, with the **constituents authoritative and the key derived from them**: an entry
whose stored constituents do not hash to its own key is reported as malformed and does not suppress,
exactly as a missing `reason` is. The hash computation, the `anchor/v<N>` versioning, and the four
entry dispositions belong to that convention and are deliberately not re-derived here; this plugin's
own contribution, what each constituent holds for an overengineering finding, is owned by
`context/findings-artifact.md` under "Finding ids".

Two obligations this plugin takes on top of the convention:

- **Offered, never taken.** `overengineering:realign` proposes an entry, shows it, and writes it only
  on an explicit yes, behind the same per-item gate that authorized the remediation. A producer that
  wrote one unprompted would record an acceptance nobody made.
- **Visible, never silent.** On the next walk the producer reports every suppressed finding with its
  reason, date, and contributing layer, and every entry that did *not* suppress, including each
  personal-only and each malformed one. **A targeted run reports what it examined**: it computes
  dispositions only for entries with a site in its `targets` and marks the rest **not evaluated this
  run**, per `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, section "Re-run merge semantics".
  Silence is what this rule forbids; a pointed run saying which entries it did not reach is the
  opposite of silence.

Every config file this page names is excluded from the audit's own scan set, so recording a
judgment does not perturb the next run's inputs: `<home>/overengineering.yaml`,
`<home>/overengineering.local.yaml`, and each old-path file present, applied or not.

## Consumer `.gitignore`

The personal override is gitignored by the cascade's one recursive line, which covers every current and
future surface at once (`docs/conventions/**/*.local.*` for the default home):

```gitignore
<home>/**/*.local.*
```

Keep the older `.claude/**/*.local.*` line while `.claude/overengineering.local.md` exists.

No skill in this plugin writes the consumer's `.gitignore`.

## Trades recorded, so they are not silently re-litigated

- **Config and suppressions share one file.** The findings-artifact contract fixes
  the team file, `<home>/overengineering.yaml` (or, in the dual-read window, the old
  `.claude/overengineering.md` while it supplies the team layer), as the home of the durable
  judgment record, and an adjacent plugin in
  this marketplace deliberately split the two so a config diff reads as a policy change and a
  suppression diff reads as an accepted finding. Here they are the same class of change, both being
  statements about what this plugin may recommend, and both resolve through the same policy-floor
  rules in the same pass, so one surface is one file to gitignore, one file to review, and one merge
  to reason about. Revisit if a consumer demonstrates a review workflow the shared file defeats.
- **No expiry key on a suppression**, per the finding-suppression contract: an expiry would be a
  second staleness mechanism competing with the disposition rules that already retire an entry the
  moment its finding is gone.
- **`off` is team-layer-only rather than forbidden outright.** The locked requirement is that a
  consumer can empty the protected set; the hazard is that a *personal* layer can. Restricting the
  direction rather than the capability satisfies both.
