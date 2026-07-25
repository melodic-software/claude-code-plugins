# Finding suppression — the deliberately-kept-finding record

Owner doc for the consumer-tracked record that says "this audit finding is known, accepted, and must
not resurface". It declares the **keys**, the per-entry shape, and the merge form; how the record's
layers resolve is the [config cascade](../config-cascade/README.md) convention's axis, and this doc
points there rather than restating it.

`contract_version` for the keys below lives in [`CHANGELOG.md`](CHANGELOG.md). The cascade contract
versions independently, per its own boundary rule.

## What this is for, and what it is not

A finding an operator has judged and decided to keep must not be re-reported forever — an audit
whose report is permanently noisy is an audit nobody reads. But a suppression can also hide a real
defect, so the shape below is deliberately stricter than a bare id list.

Not for: a finding that is simply wrong (fix the check), a file the audit should never have read
(that is an exclusion, derived from the target's own state, not a suppression), or a temporary
silence (there is no expiry key — see the trade recorded at the bottom).

## Where the record lives

`.claude/<surface-name>.md` in the consuming repository, layered across the three cascade layers. The
consuming plugin names its own surface — the first adopter, `claude-config`'s `audit-pass` skill,
uses `audit-pass.md`, giving:

| Order | Layer | Path |
|---|---|---|
| 1 | user-global | `~/.claude/audit-pass.md` |
| 2 | team (tracked) | `${CLAUDE_PROJECT_DIR}/.claude/audit-pass.md` |
| 3 | local overlay (gitignored) | `${CLAUDE_PROJECT_DIR}/.claude/audit-pass.local.md` |

All three layers absent is a valid state: no suppressions.

The record is **excluded from the audit's own scan set**. Otherwise recording a suppression changes
the tree, perturbs the next run, and makes any idempotence claim about that run unfalsifiable.

## File format

Markdown with a fenced YAML block — human-readable in review, greppable from a shell.

````markdown
# audit-pass suppressions

```yaml
suppressions:
  3f1a9c02d4b78e55:
    reason: "Nested CLAUDE.md deliberately tightens the root rule for generated code."
    date: 2026-07-24
  b7e0d1145aa93c68:
    reason: "Conflicts with org policy; exception requested, tracked in #482."
    date: 2026-07-24
```
````

## Keys

| Key | Type | Required | Meaning |
|---|---|---|---|
| `suppressions` | mapping | yes | Entries keyed by the audit's `finding_id`. **A mapping, never a list** — see below. |
| `suppressions.<finding_id>.reason` | string, non-empty | **yes** | Why this finding is accepted. A suppression with no stated reason cannot be reviewed and cannot be retired. |
| `suppressions.<finding_id>.date` | ISO-8601 date | **yes** | When it was accepted. Staleness is judged against it. |

Unknown keys are inert, per the cascade's soft-degradation rule. An entry missing `reason` or `date`
is **reported as malformed and does not suppress** — a silent partial parse would turn a formatting
slip into a lost check.

### Keyed per entry, never a closed list

A list of ids is *taken whole*. Under any layering scheme, a personal layer supplying a list would
discard every entry the team layer holds — so one personal suppression would silently un-suppress
the entire team's accepted set, and the operator would see a report full of findings they had already
judged.

A mapping keyed by `finding_id` merges **per key**: a later layer's entry for id X wins for X only,
and every id the later layer does not mention keeps the earlier layer's entry.

**Merge form: per-key override**, declared here as the cascade convention requires.

### Policy-floor precedence inversion

This surface is in the cascade's sanctioned **policy-floor precedence-inversion** class: on a direct
conflict for the same `finding_id`, **the team layer wins**, the reverse of the default.

It qualifies on all three of the class's conditions:

1. The team layer is a genuine policy floor — a personal overlay suppressing a finding the team never
   accepted is exactly the "personal layer weakens a team standard" failure the class exists to
   prevent structurally.
2. Personal layers stay add/tighten-only: a personal layer may add a suppression for an id the team
   layer does not mention, and may *narrow* one, but a personal entry never overrides a team entry
   for the same id.
3. **Provenance is reported.** When the audit emits its `suppressed` section, each entry names the
   contributing layer, so a reader can tell a team floor from a personal addition.

Condition 3 is behavioral, not declarative: a surface that declares the inversion but does not report
which layer supplied each entry has not met the class.

## Obligations on a consuming skill

A skill reading this surface:

1. Resolves layers per the cascade's algorithm — anchor at the repo root, read every layer that
   exists, merge per-key, report the contributing layer, degrade soft on a malformed layer.
2. Emits a `suppressed` report section listing every suppressed finding with its reason, date, and
   contributing layer. Suppression is visible, never silent.
3. Reports an entry whose `finding_id` matches no current finding as **stale**, rather than ignoring
   it. A suppression that has outlived its finding is how a corpus quietly loses a check.
4. **Refuses** a suppression that would be written into a path the audit excludes — a byte-identical
   cluster copy, a vendored tree, a worktree — and names the canonical source instead. Writing a
   marker into a synced copy makes it differ from its siblings and breaks the sync path.
5. Never edits a user-scope file to record a suppression. User-scope findings are routed as
   recommendations; a marker written into `~/.claude/**` is an in-place edit by another name, and
   that tree is commonly owned by a dotfiles manager that will fight it.

## Trades recorded, so they are not silently re-litigated

- **Reason and date are required, and this has no precedent on any suppress path in this
  marketplace** — the closest analogue stores bare ids. That precedent is not transferable: it
  justifies its bare form by arguing its opt-out can only cause junk to be *missed*, never *removed*.
  A findings suppression can hide a real defect and cannot make that argument.
- **One in-repo precedent went the other way and is deliberately not followed:** the `review` plugin
  declined to add a config surface for smell suppression, letting it ride existing project docs.
  Rejected here because a suppression that cannot be keyed cannot be checked for staleness.
- **No expiry key.** An expiry would be a second staleness mechanism competing with obligation 3,
  which already retires an entry the moment its finding is gone. Revisit if a consumer demonstrates a
  suppression that should lapse while its finding persists.
- **Claude-specific location, for now.** Every surface the first adopter audits is a Claude Code
  artifact, so a finding about one belongs under `.claude/`. A cross-vendor instruction surface
  entering scope would break that premise, and the location argument must then be re-derived rather
  than inherited.

## Implementers

Conformance is tracked once, in the cascade contract's own
[Implementers table](../config-cascade/README.md#implementers) — that table already carries every
layered consumer surface in the fleet, and a second table here would be the same rows in two places,
drifting apart the first time one is updated alone.

The first adopter is `claude-config`'s `audit-pass` skill.
