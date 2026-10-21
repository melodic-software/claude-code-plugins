---
description: "Audits a repository's existing enforcement surface (hooks, agent instructions, CI lanes, gate scripts, branch protection, forge apps, integrations) and reports which mechanisms no longer earn their keep; security-class items cap at flag-for-human. Read-only. Use when the user asks whether their CI, hooks or gates are overengineered or still earn their keep. Not for proposing new automation."
argument-hint: "[layer ...] [unattended]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Audit the enforcement surface for mechanisms no longer earning their carry cost
---

**Arguments.** `[layer ...] [unattended]`. Layer: agent-hooks|agent-instructions|repo-hooks|vcs-hooks|ci-lanes|gate-scripts|satellite-workflows|branch-protection|forge-apps|external-integrations|all (default: all)

## Repository context. Gather first

Run each as its own Bash call, never combined into one invocation:

- Branch, `git symbolic-ref --quiet --short HEAD`
- Shallow clone, `git rev-parse --is-shallow-repository`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on.

## Purpose

Walk the enforcement surface that governs work in this repository and report which mechanisms still
earn their carry cost. Every incumbent is a retirement candidate until evidence earns its keep, and
silence is not evidence in either direction.

Which automation is MISSING is `/harness-config:audit-automation-gaps`'s question. Route a gap that
surfaces mid-walk there when that plugin is installed; otherwise record it in the findings artifact
as an observation for the human. This walk never proposes new automation.

**The surface is everything that governs work here, wherever it is registered**, including settings
scopes merged from outside the tree and forge controls in a control plane. Out-of-repo items are
audited like any other; only their remediation changes, to a delegation (§12).

Read `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` before judging anything and cite its sections
in findings rather than paraphrasing them: the verdict ladder (§6), evidence tiers (§2), the three
liveness questions (§3), intent reconstruction (§4), rediscovery (§5), protected classes and their
cap (§7), UNPROVEN triage (§8), analogical thresholds (§9), scope boundary (§10), rollback ladder
(§11), ownership (§12). Every bare `§N` in this skill and its context files is a section of that
document. Shared docs sit under `${CLAUDE_PLUGIN_ROOT}/context/` and `${CLAUDE_PLUGIN_ROOT}/reference/`;
this skill's own docs sit under `${CLAUDE_PLUGIN_ROOT}/skills/audit/context/`.

## Read-only contract

**This skill reports only. It never mutates the surface it walks.** No hook disabled, no workflow
edited, no gate script deleted, no setting changed, no branch rule touched, not even a formatting fix
in a file it read.

The one write is the **findings artifact**, at the memory-tier home
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md` "Where it lives" defines, a self-ignored scratch
root outside tracked content. Immediately after resolving the home (step 1 of "Before the walk"),
and before any layer is walked, say: *"Read-only pass; the only file written is the findings artifact
at `<resolved path>`."*

**A run with no branch identity writes nothing at all**, and says instead: *"Read-only pass; no
branch identity resolved, so no findings artifact is written."* See "A detached checkout has no
branch identity".

**Writing the artifact from a delegated run.** Some harnesses refuse a report-shaped filename from a
delegated executor. The sanctioned route: write the full content with the file-write tool to a
neutral filename in the artifact's directory, then rename it to the contract filename. An
`unattended` run takes this route from its first write; an attended run writes the contract filename
directly and switches at the first refusal. The route covers every write of the artifact, each
per-layer checkpoint included. **Never write the artifact's content through the shell.** Where
neither route is available, say so and stop.

**One auxiliary write is sanctioned**: the once-per-session self-ignore guard, creating the memory
root's own `.gitignore` (announced) when absent, never the consumer's root `.gitignore`. Nothing else
is written.

Executing a finding belongs to `overengineering:realign`, behind an explicit per-item human gate.
Name it as the next step; never start it unasked.

## Arguments

Parse `$ARGUMENTS`:

- **Layer scope**: one or more of the **ten enforcement layers** in
  `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`'s vocabulary, `agent-hooks` through
  `external-integrations`; default `all`, meaning those ten and never the justification lane's five.
  Asked for one of the five, refuse and name `/overengineering:justify`, which owns them one target
  at a time. Record exactly the layers walked in the artifact's `scope`: merge rule 3 reads `scope`
  to close a prior finding as gone, so a layer recorded but not walked closes another producer's
  rows, and a layer absent from `scope` was not walked rather than found empty. Layer-scoped passes
  are the supported way to cover a large surface; they compose by stable finding id.
- **`unattended`** (also `--unattended`): for low-confidence intent (§4), record `OPEN-INTENT`, ask
  nothing, guess nothing. **Attended is the default**; the caller passes the flag, and the mode is
  never inferred.
- Anything else is a free-text focus hint (a path, a mechanism name). It narrows attention, not the
  layer scope; a hint that matches nothing is reported.

## Before the walk

1. **Resolve the branch identity, then the artifact home.** Read the branch call's exit status.
   **`HEAD` is never a branch identity**, and neither is a failed call; "A detached checkout has no
   branch identity" governs what an unresolved identity declines, decided here. With an identity,
   compose the home per `findings-artifact.md` "Where it lives"; any other path writes where
   `realign` never looks. **Then emit the read-only opening line.** An `unattended` run then probes
   the write path before walking: with the file-write tool, write a neutral file in the artifact's
   directory, rename it to a second neutral name there, and delete exactly that second path (the
   file-write tool's delete where offered, else one shell removal of that path). Never rename onto the
   contract filename. The probe leaves no file behind on success and, removal included, is part of
   the findings-artifact write, not another auxiliary write. A run with no branch identity has
   nothing to probe. When the write, rename or
   delete is refused, try no other route: name the refusal and every probe path still on disk, and
   stop before walking.
2. **Resolve consumer configuration**: protected categories, threshold overrides, observation window
   and suppression entries from the consuming repo's `.claude/overengineering.md` through the
   config-cascade layering, per `${CLAUDE_PLUGIN_ROOT}/reference/consumer-config.md`. All layers
   absent is valid: bundled defaults apply, and the run says so. Name a personal layer that
   materially shapes output.
3. **Load the prior artifact** if present. Write `Status: OPEN` on a finding not seen before and
   carry every other status forward verbatim; never advance, downgrade or clear one.
4. **Assess evidence availability** per tier (§2), naming the probe for each, the shallow-clone probe
   included. This leads the report, ahead of any finding (§8).
5. **Exclude** the consumer's `.claude/overengineering.md` from the scan set.

## The walk

[skills/audit/context/surface-walk.md](context/surface-walk.md) carries the layer-by-layer walk in the
artifact's enum order: each layer's discovery probes and evidence sources, the custody and
shallow-clone reads, the container granularity rule, and the per-layer write. Read it at the start
of the walk, not per layer.

- **Write the artifact per layer, as the walk proceeds**, so a run that runs out of context leaves
  its completed layers persisted for a later pass to merge into.
- **Re-read the artifact from disk immediately before each write** and merge against that copy: the
  second producer's rows sit in layers this walk never visits, and a stale merge drops them with no
  closure row (`findings-artifact.md` "Re-run merge semantics").
- **Answer the three liveness questions independently for every item** (§3).

## Verdicts and evidence

Every verdict is one of §6's tokens, argued in carry cost (§1), and **cites at least one empirical
source or is UNPROVEN naming the tier consulted and whether it was silent or unavailable** (§2).
Documentation, headers and rationale text are claims to verify, never evidence; doc-only support is
marked unverified.

An existing check is held to the enforcement ladder's guardrail criterion: read
[the Guardrail criterion section](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/enforcement-ladder/README.md#guardrail-criterion)
live. **As of**: 2026-10-21. **Recheck trigger**: the ladder's major version changes.

Protected items are audited in full: §7 caps the recommendation, not the scrutiny, and uncertain
protection status counts as protected. A threshold that fires is cited with its source and its
analogical label verbatim (§9); a threshold the consumer disabled is not cited at all, and the
qualitative bar carries the argument instead.

## Intent checkpoints

When intent reconstruction scores MEDIUM or LOW (§4):

- **Attended (default)**: ask checkpoint questions, recommendation first, one small numbered set,
  batched. Use `planning:interview`'s mechanics when installed, otherwise ask inline.
- **Unattended**: record `OPEN-INTENT` and move on. Never invent an intent.

"I don't know" is accepted: it routes the item to §8's empirical track with intent recorded as
unrecovered.

## Neighbor routing

Every route is **presence-gated**: check the plugin is installed, else take the inline fallback.
Record the route and the presence answer in the finding's `Routed-to`.

| Finding class | Route (presence-gated) | Inline fallback when absent |
|---|---|---|
| Instruction *text* that is stale, over-prescriptive, or contradicts another surface | `harness-config:audit-instructions` | Keep the finding in `agent-instructions` with its evidence; report the wording, do not rewrite it |
| An agent-layer standing-instruction ablation the evidence cannot settle | `harness-config:unhobble` | Route the item to §8's bounded ablation batch at rung 1 of §11, with the observation window and its end date recorded |
| The operator asks what to *add* rather than retire | `harness-config:audit-automation-gaps` | Say prospective additions are outside this skill's contract, and record no finding for them |
| A plugin component that does not do what its manifest or description says | `plugin-quality:audit` | Report an ordinary liveness finding (§3) on the component and stop there |

## Incumbent-first

Before proposing any remediation, search for an existing owner: a mechanism in this repo that covers
the concern, a native platform feature that covers it now (with §5's dated tech-drift check), or a
neighbor surface whose contract holds it. Ownership resolves through §12; ownerless is not a valid
terminal state.

## Custody is detected, never assumed

Assume no organization, forge, CI system, branch name or harness; the ten layers are forge-neutral
and every probe resolves what the consumer declares. Identify a managed, vendored or synced file, a
referenced shared workflow, or an organization-level policy from the consumer's own declarations (a
sync manifest, a code-owners entry, a maintained header, a documented upstream). Where custody is
upstream, remediation is a delegation (§12), never an in-repo edit.

## The report

[skills/audit/context/report-template.md](context/report-template.md) owns the output shape: the
findings artifact as the single source of truth, an inline terminal summary always, and a rendered
HTML view only as a presence-gated extra. Fields, ids, ordering, the spine/prose split and merge
semantics belong to `findings-artifact.md`.

This lane writes `schema: 2` and `mode: walk`, and omits `targets`. It reads `schema: 1` and
`schema: 2` artifacts; anything else stops the run with a visible message. Merging into schema 1
upgrades it; a row carried forward untouched keeps no `Basis`, displayed as
`not recorded (schema 1)` until re-evaluated. Every finding carries `Basis`: `measured` where a
tier-1–4 citation supports the verdict; `class-inferred` where it rests on §6's non-derivable-oracle
clause or a §7 class match and every consult was silent or tier-5-only; `unexamined` only with
`UNPROVEN`. Where both `class-inferred` and `unexamined` fit, `class-inferred` wins: the
discriminator is what the verdict rests on. The `check` constituent of every id this lane derives
carries `audit` as its producer segment.

## A detached checkout has no branch identity

`git rev-parse --abbrev-ref HEAD` answers `HEAD` on a detached checkout; `HEAD` keys every ref to one
home and passes `realign`'s branch-match check against any other ref, which is why the branch call
uses `git symbolic-ref`. Scheduled runners commonly check out detached. When the identity does not
resolve:

- **Prefer a logical ref the environment supplies**, only once it is a real branch name. Name no
  vendor's variables. Before it keys a home or fills `branch:`:
  1. **Normalize** it to `git symbolic-ref --short`'s form: strip a leading `refs/heads/` and only
     that, so `refs/heads/main` and `main` give the same home.
  2. **Validate** it: refuse it if empty, if any path segment is `.` or `..` (the slug keeps `.`, so
     `..` would escape the home), or if `git check-ref-format --branch -- <value>` exits non-zero.

  A value failing either step is absent. A value that passes is the identity for both the home and
  `branch:`, and the report says it came from the environment.
- **Otherwise persist nothing and say why**: "detached checkout, no logical ref supplied; no branch
  identity, so no findings artifact is written". Never fall back to `HEAD`, the commit sha, or
  whatever home the slug produces.
- **Never write `branch: HEAD`, and never write the key empty or absent.** Decline the whole artifact.

**Detached in a repository and no checkout are different stops.** With **no checkout** (`git
rev-parse --show-toplevel` fails) there is no surface to audit: stop, and do not walk the working
directory as if it were a repository. A **detached checkout inside a repository** still walks and
emits the inline summary; only the persisted write is declined, stated in place of the opening
line's path. When that summary is the only record, it lists **every** finding, not the template's
capped top findings.

## Spoke paths

The `context/` files write the plugin's root directory as `<plugin-root>`, which is
`${CLAUDE_PLUGIN_ROOT}`. Substitute it before running a command or writing it into a brief.
[`${CLAUDE_PLUGIN_ROOT}/reference/spoke-paths.md` § Spoke paths](${CLAUDE_PLUGIN_ROOT}/reference/spoke-paths.md#spoke-paths)
records why, with the pointer to recheck. **As of**: 2026-10-11. **Recheck trigger**: that section is
renamed or removed, or its own recheck trigger fires.

## Next

`/overengineering:realign`. It executes accepted findings from this run's artifact.

## Gotchas

- **A layer-scoped pass is not a retirement of what it did not look at.** Findings in unwalked layers
  are carried forward untouched and marked not re-evaluated this run.
- **A zero is not a measurement.** For hook-, transform- and gate-shaped items, no recorded
  invocations is the expected reading for one that works and is heavily used (§5).
- **Two copies, one wired.** Where a guard exists in a local and a packaged form, name which copy the
  verdict is about; the rationale often lives with the copy that no longer fires.
- **A control used in a comparison gets its own liveness read** before the comparison is admitted
  (§2).
- **Never recommend weakening the practices whose output is the evidence** (§10): tests, review, type
  checking, the build, and the record-keeping that makes tiers 1 and 2 readable.
