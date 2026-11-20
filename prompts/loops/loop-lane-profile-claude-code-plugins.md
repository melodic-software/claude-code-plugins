# Loop-lane profile: melodic-software/claude-code-plugins

The filled profile for the templates in [`loop-lane-prompts.md`](loop-lane-prompts.md): the variable
values and the notes specific to `melodic-software/claude-code-plugins`. Every launch block is the
template's block with these values filled in; this file holds no copy of a block, so a fix to a
template reaches this repository's lanes with nothing to re-render. Read this when launching a lane
against that repository, or as a worked example of a completed profile.

## Contents

- [Variable values](#variable-values)
  - [Tier is not the rung](#tier-is-not-the-rung)
- [Launching](#launching)
  - [Worker lane](#worker-lane)
  - [Merge lane](#merge-lane)
  - [Attended queue, melo-desk-001](#attended-queue-melo-desk-001)
  - [Parked-decision burn-down, melo-desk-001, after the queue drains](#parked-decision-burn-down-melo-desk-001-after-the-queue-drains)

## Variable values

Filled instance for the repository in use as of 2026-07-25.

| Variable | Value |
|---|---|
| `{{REPO}}` | `melodic-software/claude-code-plugins` |
| `{{TIER}}` | `autopilot` |
| `{{STOP}}` | `--drain` |
| `{{MERGE}}` | `--merge human-only` (see [Merge lane](#merge-lane)) |
| `{{SHARD}}` | one of three values, see [Attended queue](#attended-queue-melo-desk-001) |
| `{{RUNTIME_SURFACES}}` | the block below, replacing the backticked placeholder whole |

`{{RUNTIME_SURFACES}}` value:

```markdown
**every tracked markdown file**
(`git ls-files '*.md'`). The plugin tree is the bulk of it (`SKILL.md`,
`agents/*.md`, `commands/*.md`, and every `reference/**`, `references/**`,
`context/**`, `templates/**` file at any depth), but it is not the edge:
`docs/conventions/source-control.yaml` supplies the merge lane's rung, and root
`CLAUDE.md` / `AGENTS.md` supply operating rules every agent loads. No
filename is exempt by convention either: this repo's
`tools/work-item-tracker/adapters/github/README.md` is the GitHub adapter's
operations reference, so even a README edit here can change lane behavior.
Treat a path as runtime unless you can show nothing loads it.
```

- Runtime surfaces: **not** just `SKILL.md` and `reference/*.md`, and not
  bounded by `plugins/` either. Under the fail-closed definition in the
  template's [Per-repository profile](loop-lane-prompts.md#per-repository-profile),
  **every tracked markdown file** (`git ls-files '*.md'`) is runtime for
  classification until individually proven inert. The plugin tree is the bulk
  of it: `SKILL.md`, `agents/*.md` (the installed reviewer agents among them),
  `context/**`, `references/**`, nested `reference/**`, and
  `templates/**`. But the two most behavioral files sit outside it:
  `docs/conventions/source-control.yaml` supplies the merge rung, and root `CLAUDE.md`
  supplies the operating rules every agent in this repo loads. Not even
  `README.md` is safe to exclude by name here:
  `tools/work-item-tracker/adapters/github/README.md` is the GitHub adapter's
  operations reference, loaded by `reference/tracker-seam.md` and
  `skills/work/SKILL.md`. Re-run the listing rather than reusing a count; it
  moves with every plugin added.
- Merge rung: `c2-mechanical`, live in tracked config on `main`, because
  unattended auto-merge launches at C2 only (#6202, "Amendment
  (auto-merge-safe-prs)"; see "Tier is not the rung" below).
  Effective rung today: human-only, until the promotion-evidence seam
  (#4588) returns a qualified read and the launch drops
  `--merge human-only`.
- Work-class labels: none is read; untrusted provenance is `provenance: untrusted`.
- Stamped `agent-ready` items: **every open one carries a class label**, and
  the population is overwhelmingly `scoped`, with `mechanical` and
  `structural` in low single digits. No rung reads the label: once a rung's
  promotion cells are promoted, every item but `untrusted-provenance` is
  merge-eligible there, an item with no label included.

  **No absolute count is recorded here, deliberately.** The worker lane
  drains the population continuously, so any number written here is wrong
  before it is read. Run the classification-count command in the template's
  [Per-repository profile](loop-lane-prompts.md#per-repository-profile), the
  one returning `fetched`, `classified`, and `body_only`, and use what it
  returns; a quoted figure describes a repository that no longer exists.
- No autonomy binding file exists, so the C2 promotion evidence above is
  not recorded here.
- Lane telemetry sinks (exact title match; excluded from triage frontier):
  `Lane telemetry: work-loop`, `Lane telemetry: babysit-loop`, and
  `Lane telemetry: attend-queue`. Launch config may pin a different issue via
  `lanes[].telemetry.issue`; when unset, resolve each sink live by its exact title.

### Tier is not the rung

`autopilot` is the maximum the prompt can set. It widens six of the seven
autonomy dimensions: discovery scope, fixing, thread resolution, draft
elevation, barrier handling, escalation posture. It does **not** raise
*standing* merge authority, which binds from the tracked config alone.

The skill carries one named exception: an invocation line typing both the
`autopilot` tier keyword and the dedicated raise argument
`--merge c3-this-run` widens that one invocation's merge rung to C3. It
changes nothing here: the merge lane passes `--merge human-only`, and the
raise fires only on its own dedicated token, which that launch does not carry.
The tracked rung stands at `c2-mechanical` (below), so the raise would widen
one invocation to C3 here, which unattended launches do not take (#6202).
Treat it as dormant in this repository, and do not swap `{{MERGE}}` for the
raise token to wake it.

So the two knobs are independent, and both are needed for "merge things
overnight without me":

- **Tier `autopilot`**: `{{TIER}}` above. Already maximal.
- **Merge rung**: one line in `docs/conventions/source-control.yaml` on `main`.
  Now `c2-mechanical`, because unattended auto-merge launches at C2 only
  (#6202, "Amendment (auto-merge-safe-prs)", item 22). A raise follows the
  path #1388 prescribed: amend the guardrail contract first, then flip the
  tracked config. Never the reverse.

`full-autonomy` as a rung **adds nothing over `c3-autonomous`**: both need
every promotable cell and admit the same PRs. C5 `untrusted-provenance`,
meaning fork PRs and outside contributions, is excluded unconditionally: no
rung, no tracked config, and no invocation argument reaches it.

The governing policy is `plugins/autonomy/reference/guardrails.md`'s matrix,
which sets C3 merge policy to auto-merge eligible after per-class promotion
trigger, with the C3 auto-merge evidence predicate in the promotion table of
`plugins/autonomy/reference/guardrails/work-classes.md`. Predicate thresholds
are suggested defaults the org may bind lower; ratifying the rung flips ahead
of the suggested evidence is an operator choice the contract records.
Demotion, whether from a post-merge gate failure, a human revert, or
verification divergence, remains the contract's automatic fail-closed discipline (its
enforcement wiring into the lane's merge partition is tracked in #1695),
and C5 `untrusted-provenance` never promotes.

No rung reads a work class: an item with **no `work-class:` label** partitions
like any other, and a `Work-class: C<n>` body trailer is operator context only.

---

## Launching

One worker lane and one merge lane, on different machines; neither on the
attended box. Fill each template block with the values above and paste it.

### Worker lane

Launch from a checkout of the repo with
[1. Worker lane](loop-lane-prompts.md#1-worker-lane), filled with `{{REPO}}`
and `{{RUNTIME_SURFACES}}`.

### Merge lane

Any machine except the attended one. Fill
[2. Merge lane](loop-lane-prompts.md#2-merge-lane) with `{{REPO}}`, `{{TIER}}`,
`{{STOP}}` and `{{MERGE}}`, which renders its first line as
`/loop /source-control:babysit-loop melodic-software/claude-code-plugins autopilot --drain --merge human-only`.

**`--merge human-only` is deliberate here, and stays until #1695 lands.**
This repository's tracked config resolves `c2-mechanical` (unattended
auto-merge launches at C2 only, #6202), so without the override the
lane would auto-merge C2 PRs. Two reasons to keep the override: the ratification
ran ahead of the suggested evidence predicates, and this repository has
recorded **zero autonomous merges ever**. The lane's rung partition also
does not yet resolve the effective promotion state against telemetry, so
the contract's automatic fail-closed demotion is declared but not wired
into the merge decision (#1695). An argument may always select a *lower*
rung than the tracked config, never a higher one, which is exactly what this does.
Drop the flag only after #1695 wires effective-promotion resolution into
the partition and the evidence predicate is met. Until then the lane's
effective rung here is human-only.

### Attended queue, melo-desk-001

Fill [3. Attended queue](loop-lane-prompts.md#3-attended-queue) with `{{REPO}}`,
`{{RUNTIME_SURFACES}}` and one `{{SHARD}}` per terminal. Each terminal launches
from its own worktree of the repo. attend-queue binds to its working directory,
and two lanes never share one.

A non-overlapping three-way split, each value a predicate the attention view's
own rows satisfy:

- `[escalated]`
- `[intake] where item number is even`
- `[intake] where item number is odd`

No fourth floater. With no row-level claim, an overlapping bucket means two
terminals mutating the same row.

### Parked-decision burn-down, melo-desk-001, after the queue drains

Fill [3b](loop-lane-prompts.md#3b-parked-decision-burn-down-attended-on-demand)
with `{{REPO}}` and `{{RUNTIME_SURFACES}}`. Same terminal and worktree as the
attended queue when run inside that session; its own worktree when run
standalone.
