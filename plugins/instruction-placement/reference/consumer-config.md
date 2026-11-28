# instruction-placement: consumer configuration

Owner doc for this plugin's tracked configuration file: `<home>/instruction-placement.yaml` in the
consuming repository, layered per the consuming marketplace's config-cascade convention. Every layer
is optional, and all of them absent is a valid state that means no suppressions.

The surface carries one key today, `suppressions`: the durable record of the findings an operator has
declined. It is declared here rather than in the plugin's `README.md` because the cascade's boundary
rule puts key ownership in the concern's own owner doc or in the plugin's bundled reference. The
README summarizes and points here.

## Why this is not `userConfig`, and not the memory tier

The plugin's `userConfig` block stays where it is: the breadth ceiling and the index row cap.
Those are personal, enable-time dials, and a personal value for any of them
changes what one operator's own report ranks while the finding it moves is still reported.

A decline is not a dial. It removes a finding from every future report, so a gitignored personal
override carrying one would hide a proposal the team never judged, the hole the artifact protocol
names when it says `userConfig` "is not a coordination surface for repository artifacts".

Nor can a decline live in the memory tier beside the findings artifact. A memory document is visible
only in the checkout that wrote it: a sibling worktree never sees it, and nothing carries this file
class across.
A judgment that has to outlive the checkout has to be **tracked**, and git is the mechanism that
carries it.

## Layers and merge semantics

The config-cascade layers, lowest first
([the layers](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md#the-layers)):

| Order | Layer | Source |
|---|---|---|
| 0 | plugin default | no suppressions |
| 1 | `userConfig` | none: a decline is a repository's judgment, so no `userConfig` option holds one (see above) |
| 2 | team (tracked) | `<home>/instruction-placement.yaml` |
| 3 | personal override (gitignored) | `<home>/instruction-placement.local.yaml` |

Every path is relative to the repository root (`git rev-parse --show-toplevel`; on a
multi-repository run, the worktree that run names). `<home>` is the convention home that the marked
pointer region in the root `AGENTS.md` or `CLAUDE.md` binds, and `docs/conventions` when no region
binds one. [Config locations](config-locations.md) lists where every plugin's config lives.

**Merge form: per-key override**, declared here as the cascade convention requires. Entries merge per
`finding_id`: a later layer's entry for one id wins for that id only, and every id it does not
mention keeps the earlier layer's entry. Wholesale replacement is forbidden, because a layer
supplying a closed list would discard every entry the team layer holds.

**`suppressions` sits in the cascade's sanctioned policy-floor precedence-inversion class.** On a
direct conflict for one `finding_id` the **team layer wins**, the reverse of the default. A
personal-layer entry for an id the team layer does not carry **does not suppress**: it is read,
reported as `personal-only, not applied`, and named with the layer that supplied it, since absence
from the team layer is the team's unsuppressed state. Whenever a personal layer materially shapes
output, the run names the contributing layer. That reporting is what makes the class hold, and it is
behavioral rather than declarative.

Files at old `.claude/` or `~/.claude/` paths are not read.

## File format

A YAML file, checked against
[`schemas/instruction-placement.schema.json`](../schemas/instruction-placement.schema.json):

```yaml
suppressions:
  866c7f4e04652643:
    check: instruction-placement/audit/demote
    claim: narrower-scope:path-scoped-rule
    sites:
      - surface: CLAUDE.md
        anchor/v1: "958d10fb"
    reason: "Kept always-loaded on purpose: contributors read it before their first commit."
    date: 2026-09-06
  3f63ad6cc4466c0a:
    check: instruction-placement/audit/promote
    claim: unloaded-convention:nested-agents-md
    sites:
      - surface: docs/deployment.md
        anchor/v1: "f2146d4b"
    reason: "Owned by the release runbook; promoting it would fork the source of truth."
    date: 2026-09-06
```

Unknown keys are inert at runtime per the cascade's soft-degradation rule; the schema check a
repository runs in CI rejects an unknown top-level key. An entry missing any required key is
reported as malformed and does not suppress.

**The entries above are derived, not illustrative.** Their `anchor/v1` values are this plugin's
anchor over the enclosing heading paths `## Test conventions` and `## Deployment` → `### Release checklist`;
their keys are the finding-suppression contract's `finding_id` over the same constituents. The
derivation of both is owned by `context/findings-artifact.md` under "Finding ids and their
constituents". Anyone editing an example re-derives the anchor and then the key with `scripts/detect.sh identity`,
never by hand, in that order:
editing an anchor changes the key that hashes it, and an entry whose constituents no longer hash to
its own key is reported as malformed and suppresses nothing. A hand-written example would be an
example nobody can copy.

## Keys

| Key | Type | Class | Meaning |
|---|---|---|---|
| `suppressions` | mapping | policy-floor | The durable record of declined findings, keyed by `finding_id`. |

### `suppressions`

The durable judgment record: a finding the operator declined, persisted so it survives the branch
switches, other worktrees, removed memory roots, and reclaimed containers that lose the memory-tier
findings artifact.

**The entry format is the marketplace's finding-suppression contract, not this plugin's.** A mapping
keyed by `finding_id`, each entry carrying all five required keys, `check`, `claim`, `sites`,
`reason`, and `date`, with the **constituents authoritative and the key derived from them**: an entry
whose stored constituents do not hash to its own key is reported as malformed and does not suppress,
exactly as a missing `reason` is. The hash computation, the `anchor/v<N>` versioning, and the four
entry dispositions belong to that convention and are deliberately not re-derived here; this plugin's
own contribution, what each constituent holds for a placement finding, is owned by
`context/findings-artifact.md` under "Finding ids and their constituents".

Three obligations this plugin takes on top of the convention:

- **Offered, never taken.** `instruction-placement:realign` proposes the entry, shows it in full, and
  writes it only on the operator's explicit yes, the same per-item gate that authorizes a move,
  reused for the decision to stop being asked. A skill that wrote one unprompted would record an
  acceptance nobody made. `instruction-placement:delta` and `instruction-placement:audit` never write
  this file at all; they only read it.
- **Visible, never silent.** Every run reports each suppressed finding with its reason, date, and
  contributing layer, and every entry that did *not* suppress: each `personal-only, not applied` and
  each malformed one. A scoped run reports what it examined: it evaluates only entries with a site in
  its scope and marks the rest **not evaluated this run**.
- **Team layer only.** A decline is written to `<home>/instruction-placement.yaml` so git carries
  it to every checkout, never to the personal override or `~/.claude/**`. The
  convention forbids editing a user-scope file to record a suppression. A personal draft is read,
  reported, and left for the operator to promote.

**Declared deviation: a fifth disposition for a scoped run.** The convention requires a skill to
resolve every entry to exactly one of four dispositions. `instruction-placement:audit` accepts a
path argument, and an entry whose site lies outside that path was not examined. Reporting it
`CLOSED` would be false, and `CLOSED`'s own accounting would then have to call it an unexplained
disappearance and fail the run's self-check. **`not evaluated this run` is therefore added, never
substituted**: it applies only to a scoped run, only to entries outside the scope, and every entry
inside the scope still resolves to one of the convention's four. A full run never emits it. The
deviation is additive and reporting-only: no entry suppresses on it, and no entry escapes a
disposition because of it.

`<home>/instruction-placement.yaml` and `<home>/instruction-placement.local.yaml` are **excluded from the audit's own scan set**. Otherwise
recording a decline would change the instruction layer the next run sweeps, and any idempotence
claim about that run would be unfalsifiable.

## Consumer `.gitignore`

The personal override is gitignored by the cascade's one recursive line, which covers every current and
future surface at once, with `<home>` written out (the default home shown):

```gitignore
docs/conventions/**/*.local.*
```

No skill in this plugin writes the consumer's `.gitignore`.

## Trades recorded, so they are not silently re-litigated

- **Suppressions on a tracked surface, the diff spine in the memory tier.** The two are different
  kinds of state: a spine is recomputed by the next run and is worthless outside the checkout that
  produced it, while a judgment is expensive to reproduce and worthless *inside* only one checkout.
  Splitting them is what makes a decline durable without committing a snapshot of detector output.
- **Config and suppressions share one file, and today suppressions are the only key.** The plugin's
  dials stay in `userConfig` because they are personal and harmless; the surface exists for the one
  class of setting that is neither. A future key that is policy rather than taste joins it here
  rather than minting a second file.
- **No expiry key**, per the finding-suppression contract: an expiry would be a second staleness
  mechanism competing with the dispositions that already retire an entry the moment its finding is
  gone.
