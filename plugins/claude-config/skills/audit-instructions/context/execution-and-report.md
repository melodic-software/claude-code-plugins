# Execution model and report contract

The parent standing record for `/claude-config:audit-instructions` run shape and finding
identity. Phase B's lane mechanics stay in [`../SKILL.md`](../SKILL.md) ("Lane sizing", "Run
files and resume") and [`../scripts/lane-runs.sh`](../scripts/lane-runs.sh). Report keying stays
in [`report-keying.md`](report-keying.md). Persist mechanics stay in
[`persist-findings.md`](persist-findings.md). This file states only the two contracts those
surfaces implement, so a later change to either lands here first.

## Execution model

Lanes are sized by a token budget stated as a **fraction of the lane model's own context
window**, never as a shipped line count. The fraction is 0.25; the byte estimate is 3.5 bytes
per token. The line figure is derived per run from measured bytes per line over the in-scope
files. The glossary citation and recheck trigger live on the "Lane sizing" heading in the skill
body and are not restated here.

Plugins stay atomic. A plugin whose in-scope surface text exceeds the budget splits by skill
into lanes of its own, and the Phase D cost line names each split. A single skill larger than
the budget still gets one lane and is named as over-budget. Concurrency is 3 to 5 lanes.

`--unattended` is declared by the caller in the invocation and never inferred from the session.
With it, the ~20-dispatch confirmation becomes a cost-line disclosure of planned and actual
dispatch counts. Without it, the run still asks before crossing that bound.

Per-lane reports live at
`${CLAUDE_PLUGIN_DATA}/audit-instructions/runs/<state-key>/<run-id>/lanes/<lane-id>.md`. Each
ends with a completion marker that carries the lane's input digest: ordered file list and
content hashes, partition digest, catalog version, conflict-criteria version, prompt digest,
harness version, resolved target model, and every behavior-affecting argument (`scope`,
`--opinion`, `--no-stopping-condition`). `last-audit.md` stays at
`audit-instructions/<state-key>/last-audit.md`.

`--resume` re-runs only lanes whose completion marker is absent or whose digest changed. It
selects the latest run id under the state key. The lease is `audit-pass`'s `run-state.sh`
(`stale_after_s`, `skew_grace_s`, `owner_epoch`, released tombstone), invoked with
`--plugin-data ${CLAUDE_PLUGIN_DATA}/audit-instructions`. A live lease is refused, naming
`heartbeat_at` and `stale_after_s`. The skill is read-only, so it takes a lease and no lock.

In a marketplace repository (`.claude-plugin/marketplace.json` present), `plugins/**` is the
editable set. The installed cache is read for residency only. Cache-commit versus HEAD drift is
named in the report. [`../reference/conflict-criteria.md`](../reference/conflict-criteria.md)
"Known limit" owns that rewrite.

## Report contract

Findings adopt `audit-pass`'s identity whole:
[`../../audit-pass/reference/finding-identity.md`](../../audit-pass/reference/finding-identity.md)
owns the tuple, `anchor/v1`, the heading-path discriminator, `finding_id/v1`, and `group/v1`.

```text
identity = (check, claim, sites)
```

- **`check`** is `claude-config/audit-instructions/<id>`, where `<id>` is the catalog id as the
  report prints it (`I33`, `I28-a`). Sub-rows keep their own id.
- **`claim`** is a per-check template, never free prose. Free prose in `claim` is a hard error.
- **`sites`** is sorted `(surface, anchor)` pairs. A check that fires at several sites reports
  one finding per site, sharing one `group`. **I15 is the one pairwise claim**: a cross-surface
  conflict is one finding with two sites, never two linked findings. Lane encounter order does
  not change the id.
- **`anchor`** is an excerpt anchor (`e:`) over the flagged sentence, discriminated by the
  enclosing heading path. No check in this catalog takes a whole-surface (`s:`) anchor: that
  form survives the edit that remediates the row.

`primary_site`, the `Surface:Line` cell, the rendered heading path, and the Finding and
Proposed change prose are presentation. None of them enters the hash.

Two runs over an unchanged tree yield identical `finding_id` values. Editing an I33 opener
changes that finding's id.

`--persist-findings` emits scanner families I28 and I29 today. The standing admission also
covers I30, I31, I32, and I33 as `Auto-applicable: No`, through a lane-fed emit path beside the
scanner-fed one, with an emitting fall-through for the judgment-selected rules (I31, I33), a
`Confidence` value the detector-findings contract defines for a model-lane finding, and a
counted decline for frontmatter-located I32 rows. The emit script and crosswalk rows are the
persist unit's work; this file records the contract they satisfy. Until those rows exist, I30
to I33 stay in the human report and are declined `no-severity-crosswalk-row` rather than
silently dropped.

Phase C verifies every proposal. No sampling, and no finding class that carries a diff is
exempted from verification. I33's per-plugin roll-up is presentation only: each spoke remains
its own finding with its own excerpt anchor.
