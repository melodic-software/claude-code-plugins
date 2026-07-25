# Finding suppression — the deliberately-kept-finding record

Owner doc for the consumer-tracked record that says "this audit finding is known, accepted, and must
not resurface". It declares the **keys**, the per-entry shape, and the merge form; how the record's
layers resolve is the [config cascade](../config-cascade/README.md) convention's axis, and this doc
points there rather than restating it. How a consumer *derives* the id and its constituents is that
consumer's own contract, not this one's.

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
  283d05878bdf5936:
    check: claude-config/audit-instructions/nested-override
    claim: nested-tightens-root
    sites:
      - surface: .claude/rules/generated.md
        anchor/v1: "e:9c02d4b78e55:c30cc60d"
    reason: "Nested rule deliberately tightens the root rule for generated code."
    date: 2026-07-24
  c5e64c89b4cf4377:
    check: claude-config/audit-instructions/cross-layer-conflict
    claim: contradicts
    sites:
      - surface: CLAUDE.md
        anchor/v1: "e:1145aa93c681:070ee98f"
      - surface: "managed:CLAUDE.md"
        anchor/v1: "e:b7e0d1145aa9:ada6cfc2"
    reason: "Conflicts with org policy; exception requested, tracked in #482."
    date: 2026-07-24
```
````

## Keys

| Key | Type | Required | Meaning |
|---|---|---|---|
| `suppressions` | mapping | yes | Entries keyed by the audit's `finding_id`. **A mapping, never a list** — see below. |
| `suppressions.<finding_id>.check` | string | **yes** | The check that raised it, as the consumer qualifies checks. |
| `suppressions.<finding_id>.claim` | string | **yes** | The canonical claim id plus bound parameters, never free prose. |
| `suppressions.<finding_id>.sites` | list of `{surface, anchor/v<N>}` | **yes** | **Every** site the finding is about — two for a cross-surface finding, not one plus a footnote. Order in the file is immaterial; the consumer sorts canonically before hashing. |
| `suppressions.<finding_id>.reason` | string, non-empty | **yes** | Why this finding is accepted. A suppression with no stated reason cannot be reviewed and cannot be retired. |
| `suppressions.<finding_id>.date` | ISO-8601 date | **yes** | When it was accepted. Staleness is judged against it. |

Unknown keys are inert, per the cascade's soft-degradation rule. An entry missing any required key
is **reported as malformed and does not suppress** — a silent partial parse would turn a formatting
slip into a lost check.

**The keys and anchors in the example above are derived, not illustrative.** They were hand-written
once and did not derive, which meant copying or scaffolding from this document produced entries the
consumer rejects as malformed — the authoritative example could not suppress anything. The anchor
suffix is the excerpt's duplicate discriminator, `sha256(heading_path)` truncated to 8 hex, and is
**never a positional ordinal**; the three shown correspond to enclosing heading paths
`## generated code`, `## repository rules`, and `## instruction precedence`. Anyone editing the
example must re-derive the affected anchors and then both keys:

```python
import hashlib
US = '\x1f'

def discriminator(heading_path):              # heading_path: ordered enclosing headings
    return hashlib.sha256(US.join(heading_path).encode('utf-8')).hexdigest()[:8]

def finding_id(check, claim, sites):          # sites: [(surface, anchor), …]
    parts = [check, claim]
    for surface, anchor in sorted(sites, key=lambda p: (p[0].encode(), p[1].encode())):
        parts += [surface, anchor]
    return hashlib.sha256(US.join(parts).encode('utf-8')).hexdigest()[:16]
```

This is the same rule the consumer enforces on every entry, so an example that does not satisfy it is
a defect in the document rather than a special case. Both halves are shown because editing an anchor
changes the key that hashes it — fixing one and not the other is how the example went stale the first
time.

### Constituents, not a bare id

The id alone is a one-way hash. It answers "is this exact finding still present" and nothing else, so
a record built on it can only ever classify an entry as matched or gone — a partial match is not
computable from it, and no carry-forward rule can be written on top of one. Storing the constituents
is also what lets a human review the record: an operator auditing a year-old entry reads what was
accepted rather than a hex string.

**The constituents are authoritative and the key is derived from them.** An entry whose stored
constituents do not hash to its own key is reported as malformed and does not suppress — the same
disposition a missing `reason` gets, and for the same reason. A hand-edited constituent left beside a
stale key would otherwise silently stop suppressing, which is a lost decision rather than a lost
check.

A site's anchor **key** carries the algorithm version (`anchor/v1`), so a site may hold several
versions at once and an entry written under one keeps matching until both the record and the run have
moved past it. Comparison uses the greatest version both sides carry.

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

1. The team layer is a genuine policy floor — a personal layer hiding a finding the team never
   accepted is exactly the "personal layer weakens a team standard" failure the class exists to
   prevent structurally.
2. Personal layers stay add/tighten-only, and on **this** surface adding a suppression is a
   *loosening*, not an addition — fewer findings reach the operator. So the rule that makes the
   condition hold is stated directly: **a personal-layer entry for a `finding_id` the team layer does
   not carry does not suppress.** It is reported as `personal-only, not applied`, naming promotion to
   the team layer as what makes it take effect. Absence from the team layer *is* the team's
   unsuppressed state, so honoring a personal-only entry would supply exactly the looser value the
   condition forbids.
3. **Provenance is reported.** When the audit emits its `suppressed` section, each entry names the
   contributing layer, so a reader can tell a team floor from a personal draft.

Condition 3 is behavioral, not declarative: a surface that declares the inversion but does not report
which layer supplied each entry has not met the class.

**What the inversion itself decides is narrower than it looks, and saying so is the point.** The
constituents-hash-to-the-key rule means two entries sharing a `finding_id` have identical `check`,
`claim`, and `sites` by construction — the only fields that can differ are `reason` and `date`. So
the inversion protects the team's recorded *justification* for an accepted finding. Which findings
are visible is condition 2's rule, not the inversion's; attributing it to the inversion is what let
the gap sit unnoticed.

A personal layer is therefore a **draft** surface on this contract: an entry there is read, reported,
and attributed, and takes effect only once promoted to the team layer.

## Obligations on a consuming skill

A skill reading this surface:

1. Resolves layers per the cascade's algorithm — anchor at the repo root, read every layer that
   exists, merge per-key, report the contributing layer, degrade soft on a malformed layer.
2. Emits a `suppressed` report section listing every suppressed finding with its reason, date, and
   contributing layer, **and every entry that did not suppress** — including each
   `personal-only, not applied` entry and each malformed one. Suppression is visible, never silent,
   and so is a suppression the operator wrote that the contract declined to enact.
3. Resolves every entry to exactly one of four dispositions, and reports every one but the first:
   - **SAME, UNCHANGED** — both anchors match, `(check, claim)` match. Applies silently.
   - **SAME, CHANGED** — exactly one anchor changed, and the other anchor plus `(check, claim, both
     surfaces)` all match. **Carries forward, marked `needs-reconfirmation`**, surfaced with the
     changed side named. Never silent: the edit may have *been* the fix attempt, and silently
     re-suppressing it hides exactly the case the operator most needs to see.
   - **OLD CLOSED, NEW OPENED** — both anchors changed, or `claim` changed, or a surface changed. The
     old entry goes **stale**, never silently dropped; the new finding is unsuppressed.
   - **CLOSED** — the finding is absent from the new run entirely. Accounted for as exactly one of:
     matched to an applied fix; matched to a successor by partial match; **retired with its check**,
     when the check that raised it is absent or renamed in the new run's detection configuration; or
     reported as an **UNEXPLAINED DISAPPEARANCE**, which fails the consuming skill's own self-check.
     An unaccounted disappearance is how a corpus quietly loses a check — which is why retirement is
     a *reported* disposition naming the retiring check and the version transition, rather than an
     exemption that would let findings vanish silently on any catalog edit. A suppression entry keyed
     to a retired check goes **stale** rather than being deleted, so a check returning under its old
     name cannot silently re-apply a decision the operator has not seen since.
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
- **Constituents are required from the first published contract, not added once a consumer needs
  them.** This record is operator-authored and commonly committed, so adding required keys later is a
  migration on somebody else's tracked data — and the migration is not mechanical, because the
  constituents cannot be recovered from the id they were hashed into.
- **A one-sided change carries the suppression forward rather than dropping it, but never
  silently.** The alternative extremes were both rejected: re-reporting from scratch churns a
  judgement the operator still holds, and re-suppressing silently hides the case where the edit *was*
  the fix attempt. `needs-reconfirmation` is what makes carrying-forward safe. Tiered matching over a
  fingerprint that is *stable enough* rather than exact is the prior art here — SARIF devotes
  Appendix B (Normative) to it, and GitHub's documented mismatch behavior is close-and-reopen.
- **Claude-specific location, for now.** Every surface the first adopter audits is a Claude Code
  artifact, so a finding about one belongs under `.claude/`. A cross-vendor instruction surface
  entering scope would break that premise, and the location argument must then be re-derived rather
  than inherited.

## Implementers

Conformance is tracked once, in the cascade contract's own
[Implementers table](../config-cascade/README.md#implementers) — that table already carries every
layered consumer surface in the fleet, and a second table here would be the same rows in two places,
drifting apart the first time one is updated alone.

The first adopter is `claude-config`'s `audit-pass` skill. It carries its own operative copy of what
it needs at run time — the record's location, the layer merge, the precedence inversion, and its
entry-disposition table — in that skill's run-contract reference, deliberately and not by oversight:
a plugin is installed into a cache where no path back to this repository resolves, so a skill that
reached here to answer a runtime question would answer nothing. This doc remains the cross-consumer
key contract; it is not a runtime dependency of any plugin, and no plugin should acquire a relative
path to it.
