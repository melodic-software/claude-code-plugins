# instruction-placement — consumer configuration

Owner doc for this plugin's tracked configuration surface: `.claude/instruction-placement.md` in the
consuming repository, layered per the consuming marketplace's config-cascade convention. Every layer
is optional — all three absent is a valid state and means no suppressions.

The surface carries one key today, `suppressions`: the durable record of the findings an operator has
declined. It is declared here rather than in the plugin's `README.md` because the cascade's boundary
rule puts key ownership in the concern's own owner doc or in the plugin's bundled reference. The
README summarizes and points here.

## Why this is not `userConfig`, and not the memory tier

The plugin's `userConfig` block stays where it is — the index-drift hook toggle, the breadth ceiling,
the index row cap. Those are personal, enable-time dials, and a personal value for any of them
changes what one operator's own report ranks while the finding it moves is still reported.

A decline is not a dial. It removes a finding from every future report, so a gitignored personal
overlay carrying one would hide a proposal the team never judged — the hole the artifact protocol
names when it says `userConfig` "is not a coordination surface for repository artifacts".

Nor can a decline live in the memory tier beside the findings artifact. A memory document is visible
only in the checkout that wrote it: the topic-docs contract marks a sibling worktree `invisible` and
forbids carrying this file class across with `.worktreeinclude` ("never baselines or raw scratch").
A judgment that has to outlive the checkout has to be **tracked**, and git is the mechanism that
carries it.

## Layers and merge semantics

Three layers, resolved in this order:

| Order | Layer | Path |
|---|---|---|
| 1 | user-global | `~/.claude/instruction-placement.md` |
| 2 | team (tracked) | `${CLAUDE_PROJECT_DIR}/.claude/instruction-placement.md` |
| 3 | local overlay (gitignored) | `${CLAUDE_PROJECT_DIR}/.claude/instruction-placement.local.md` |

**Merge form: per-key override**, declared here as the cascade convention requires. Entries merge per
`finding_id`: a later layer's entry for one id wins for that id only, and every id it does not
mention keeps the earlier layer's entry. Wholesale replacement is forbidden — a layer supplying a
closed list would discard every entry the team layer holds.

**`suppressions` sits in the cascade's sanctioned policy-floor precedence-inversion class.** On a
direct conflict for one `finding_id` the **team layer wins**, the reverse of the default. A
personal-layer entry for an id the team layer does not carry **does not suppress**: it is read,
reported as `personal-only, not applied`, and named with the layer that supplied it, since absence
from the team layer is the team's unsuppressed state. Whenever a personal layer materially shapes
output, the run names the contributing layer — that reporting is what makes the class hold, and it is
behavioral rather than declarative.

## File format

Markdown with a fenced YAML block — human-readable in review, greppable from a shell.

````markdown
# instruction-placement suppressions

```yaml
suppressions:
  6e9976d9d2e2c5a4:
    check: instruction-placement/audit/demote
    claim: narrower-scope:path-scoped-rule
    sites:
      - surface: CLAUDE.md
        anchor/v1: "4b322d9c"
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
````

Unknown keys are inert per the cascade's soft-degradation rule. An entry missing any required key is
reported as malformed and does not suppress.

**The entries above are derived, not illustrative.** Their `anchor/v1` values are this plugin's
anchor over the enclosing heading paths `## C# naming` and `## Deployment` → `### Release checklist`;
their keys are the finding-suppression contract's `finding_id` over the same constituents. The
derivation of both is owned by `context/findings-artifact.md` under "Finding ids and their
constituents". Anyone editing an example re-derives the anchor and then the key, in that order:
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
keyed by `finding_id`, each entry carrying all five required keys — `check`, `claim`, `sites`,
`reason`, `date` — with the **constituents authoritative and the key derived from them**: an entry
whose stored constituents do not hash to its own key is reported as malformed and does not suppress,
exactly as a missing `reason` is. The hash computation, the `anchor/v<N>` versioning, and the four
entry dispositions belong to that convention and are deliberately not re-derived here; this plugin's
own contribution — what each constituent holds for a placement finding — is owned by
`context/findings-artifact.md` under "Finding ids and their constituents".

Three obligations this plugin takes on top of the convention:

- **Offered, never taken.** `instruction-placement:realign` proposes the entry, shows it in full, and
  writes it only on the operator's explicit yes — the same per-item gate that authorizes a move,
  reused for the decision to stop being asked. A skill that wrote one unprompted would record an
  acceptance nobody made. `instruction-placement:delta` and `instruction-placement:audit` never write
  this surface at all; they only read it.
- **Visible, never silent.** Every run reports each suppressed finding with its reason, date, and
  contributing layer, and every entry that did *not* suppress — each `personal-only, not applied` and
  each malformed one. A scoped run reports what it examined: it evaluates only entries with a site in
  its scope and marks the rest **not evaluated this run**.
- **Team layer only, and never user-global.** A decline is written to
  `${CLAUDE_PROJECT_DIR}/.claude/instruction-placement.md` so git carries it to every checkout. The
  convention forbids editing a user-scope file to record a suppression, and this plugin never writes
  `~/.claude/**` — a personal draft there is read, reported, and left for the operator to promote.

`.claude/instruction-placement.md` and its layers are **excluded from the audit's own scan set**.
Otherwise recording a decline would change the instruction layer the next run sweeps, and any
idempotence claim about that run would be unfalsifiable.

## Consumer `.gitignore`

The overlay layer is gitignored by the cascade's one recursive line, which covers every current and
future surface at once:

```gitignore
.claude/**/*.local.*
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
