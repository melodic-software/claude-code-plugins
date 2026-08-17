# overengineering — consumer configuration

Owner doc for this plugin's configuration surface: `.claude/overengineering.md` in the consuming
repository, layered per the consuming marketplace's config-cascade convention. Every layer is
optional — zero config is a fully working state, and the bundled defaults in
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

## Layers and merge semantics

Three layers, resolved in this order:

| Order | Layer | Path |
|---|---|---|
| 1 | user-global | `~/.claude/overengineering.md` |
| 2 | team (tracked) | `${CLAUDE_PROJECT_DIR}/.claude/overengineering.md` |
| 3 | local overlay (gitignored) | `${CLAUDE_PROJECT_DIR}/.claude/overengineering.local.md` |

**Merge form: per-key override**, declared here as the cascade convention requires. The values are
scalars and closed mappings, where concatenation is meaningless — a later layer replaces an earlier
layer's value key by key, a key absent from a later layer keeps the earlier value, and wholesale
replacement is forbidden.

**Two key groups additionally sit in the cascade's sanctioned policy-floor precedence-inversion
class** — `protected_categories` and `suppressions`. On a direct conflict there the **team layer
wins**, the reverse of the default; personal layers (user-global and overlay) may extend or tighten
only, never weaken; and whenever a personal layer materially shapes output, the run **names the
contributing layer**. The remaining keys — `thresholds` and `observation_window` — take the ordinary
refinement form, where a later layer's value simply wins.

The split is not stylistic. A gitignored overlay that emptied the protected set, or suppressed a
finding the team never accepted, would recreate exactly the hole that disqualified `userConfig`.
Thresholds and the observation window carry no such hazard: a personal threshold changes what one
operator's own report ranks, and the finding it moves is still reported.

All three layers absent is a valid state — the bundled defaults apply and the run says so.

## File format

Markdown with a fenced YAML block — human-readable in review, greppable from a shell.

````markdown
# overengineering config

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

suppressions:
  230042849f499636:
    check: overengineering/audit/rule-ci-lanes
    claim: enforcement-item
    sites:
      - surface: .github/workflows/nightly.yml
        anchor/v1: "0d5658b4"
    reason: "Kept deliberately: the lane is our only pre-release smoke path."
    date: 2026-08-17
```
````

Every top-level key is optional, and so is the file. Unknown keys are inert per the cascade's
soft-degradation rule.

**The suppression entry above is derived, not illustrative.** Its `anchor/v1` is
`sha256` of the ordered locator path `[".github/workflows/nightly.yml"]` truncated to 8 hex, and its
key is `sha256` over the `US`-joined `[check, claim, surface, anchor]` truncated to 16 hex — the same
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

**Extend, narrow, empty — and which layer may do which.** Adding a category, or adding a `match`
pattern to one, is a tightening: any layer may do it, and a personal contribution is named in the
report. Turning a category `off`, or removing a `match` pattern the team layer carries, is a
weakening: **only the team-tracked layer may do it.** A personal layer's `off` is read, reported as
`personal-only, not applied`, and does not take effect — the same disposition the finding-suppression
contract gives a personal-only suppression, and for the same reason.

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
and feature-flag literature, so overriding one — or switching it off — is expected, not exceptional.

| Key | Type | Default | §9 row |
|---|---|---|---|
| `accuracy_floor` | number 0–1 | `0.5` | Accuracy floor |
| `false_positive_attention` | number 0–1 | `0.1` | False-positive attention line |
| `exercise_frequency_days` | integer | `90` | Exercise frequency |
| `staleness_age_days` | integer | `30` | Staleness gate — "older than" condition |
| `staleness_unevaluated_days` | integer | `7` | Staleness gate — "not evaluated in" condition |
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
constraint; setting both to `0` is rejected rather than silently taken — a window with no end date is
the abandonment §11 exists to prevent.

### `suppressions`

The durable judgment record: an operator's accepted-keep or REJECTED judgment, persisted so it
survives the branch switches, removed worktrees, and reclaimed containers that lose the memory-tier
findings artifact.

**The entry format is the marketplace's finding-suppression contract, not this plugin's.** A mapping
keyed by `finding_id`, each entry carrying all five required keys — `check`, `claim`, `sites`,
`reason`, `date` — with the **constituents authoritative and the key derived from them**: an entry
whose stored constituents do not hash to its own key is reported as malformed and does not suppress,
exactly as a missing `reason` is. The hash computation, the `anchor/v<N>` versioning, and the four
entry dispositions belong to that convention and are deliberately not re-derived here; this plugin's
own contribution — what each constituent holds for an overengineering finding — is owned by
`context/findings-artifact.md` under "Finding ids".

Two obligations this plugin takes on top of the convention:

- **Offered, never taken.** `overengineering:realign` proposes an entry, shows it, and writes it only
  on an explicit yes, behind the same per-item gate that authorized the remediation. A producer that
  wrote one unprompted would record an acceptance nobody made.
- **Visible, never silent.** On the next run the audit reports every suppressed finding with its
  reason, date, and contributing layer — and every entry that did *not* suppress, including each
  personal-only and each malformed one.

`.claude/overengineering.md` is excluded from the audit's own scan set, so recording a judgment does
not perturb the next run's inputs.

## Consumer `.gitignore`

The overlay layer is gitignored by the cascade's one recursive line, which covers every current and
future surface at once:

```gitignore
.claude/**/*.local.*
```

No skill in this plugin writes the consumer's `.gitignore`.

## Trades recorded, so they are not silently re-litigated

- **Config and suppressions share one file.** The findings-artifact contract fixes
  `.claude/overengineering.md` as the home of the durable judgment record, and an adjacent plugin in
  this marketplace deliberately split the two so a config diff reads as a policy change and a
  suppression diff reads as an accepted finding. Here they are the same class of change — both are
  statements about what this plugin may recommend — and both resolve through the same policy-floor
  rules in the same pass, so one surface is one file to gitignore, one file to review, and one merge
  to reason about. Revisit if a consumer demonstrates a review workflow the shared file defeats.
- **No expiry key on a suppression**, per the finding-suppression contract: an expiry would be a
  second staleness mechanism competing with the disposition rules that already retire an entry the
  moment its finding is gone.
- **`off` is team-layer-only rather than forbidden outright.** The locked requirement is that a
  consumer can empty the protected set; the hazard is that a *personal* layer can. Restricting the
  direction rather than the capability satisfies both.
