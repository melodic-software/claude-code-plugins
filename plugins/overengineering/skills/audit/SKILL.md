---
description: "Audit an existing enforcement surface of agent hooks, standing instructions, repository and version-control hooks, CI lanes, gate scripts, branch protections, forge apps, and declared integrations, under an evidence-earned-keep model: every incumbent is a retirement candidate until evidence earns its keep, every verdict cites an empirical source or is classed UNPROVEN, and security-class items are capped at flag-for-human. Read-only: it walks and reports; everything it writes unasked stays in the self-ignored memory tier, and its one tracked write (persisting the resolved artifact home to the concern file) happens only on explicit confirmation. Use when: 'audit our enforcement surface', 'is our CI overengineered', 'are these hooks still earning their keep', 'what automation can we retire', 'too many guards', 'process cruft', 'do we still need this gate', 'enforcement clutter', 'retire dead automation', 'why does this check exist'. Pass one or more layers to scope a pass, or `unattended` for a dispatched or scheduled run. Not for proposing NEW automation, and it never mutates the surface it walks. The sibling `realign` skill executes accepted findings behind a per-item human gate."
argument-hint: "[layer ...] [unattended], where layer is agent-hooks|agent-instructions|repo-hooks|vcs-hooks|ci-lanes|gate-scripts|satellite-workflows|branch-protection|forge-apps|external-integrations|all (default: all)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Audit the enforcement surface for mechanisms no longer earning their carry cost
---

## Pre-computed context

- Branch: !`git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown (no checkout)"`
- Shallow clone: !`git rev-parse --is-shallow-repository 2>/dev/null || echo "unknown (no checkout)"`

## Purpose

Walk the enforcement surface that governs work in this repository and report which mechanisms still
earn their carry cost. The posture is the inverse of a gap audit: every incumbent is a retirement
candidate until evidence earns its keep, and silence is not evidence in either direction.

**The surface is everything that governs work here, wherever it is registered.** That includes
settings scopes the harness merges from outside the tree (user, machine, organization level) and
forge controls living in a control plane. Such an item is audited like any other; what changes is
only the remediation, which is out-of-repo custody's delegation (§12). Out-of-repo is never a reason
to skip.

The method is **not restated here.** Read `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` before
judging anything and cite its sections in the findings: the verdict ladder (§6), the evidence tiers
(§2), the three liveness questions (§3), intent reconstruction (§4), rediscovery (§5), the protected
classes and their cap (§7), UNPROVEN triage (§8), the analogical thresholds (§9), the scope boundary
(§10), the rollback ladder (§11), and ownership (§12). A paraphrase of any of those in a finding is a
drift seed; a pointer is not. Every bare `§N` in this skill and its context files is a section of
that one document.

**Two doc roots, different directories.** Shared docs sit at the plugin root
(`${CLAUDE_PLUGIN_ROOT}/context/…`, `${CLAUDE_PLUGIN_ROOT}/reference/…`); this skill's lane docs sit
under `${CLAUDE_PLUGIN_ROOT}/skills/audit/context/…` and are linked relatively below, with their
plugin-relative path as the link text. Resolving one against the plugin root lands on nothing.

## Read-only contract

**This skill reports only. It never mutates the surface it walks.** No hook is disabled, no workflow
edited, no gate script deleted, no setting changed, no branch rule touched, not even a formatting
fix in a file it happened to read.

The one write it performs is the **findings artifact**, at the memory-tier home resolved through
`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`. That write *is* the deliverable, and the memory tier
is a machine-local, self-ignored scratch root outside the repository's tracked content, so writing
there is not a mutation of the repo. State this rather than leaving it to be inferred:
*"Read-only pass; the only file written is the findings artifact at `<resolved path>`."* That path
exists only once the home is resolved, so the line is emitted **immediately after that resolution**,
which is step 1 of "Before the walk", and before any layer is walked.

**Writing the artifact from a delegated run.** Some harnesses refuse a report-shaped filename from a
delegated or dispatched executor, and the `unattended` caller below is exactly that. The sanctioned
route is the file-write tool: write the full content to a neutral filename in the artifact's own
directory, then rename it to the contract's filename. **A shell content-write is never acceptable.**
It routes the deliverable around the write path the harness governs, and quoting, expansion, and
encoding silently transform what it carries. Where neither route is available, say so and stop.

**Two auxiliary writes are sanctioned, and only these.** (a) The topic-docs **self-ignore guard**:
the convention's once-per-session check that the resolved memory root gitignores itself, creating
that root-local `.gitignore` (announced) when absent. That is a memory-tier write, never the
consumer's root `.gitignore`. (b) The resolution rungs' **concern-file persistence** (rungs 2–4 of
`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`): a tracked write that happens only on the user's
explicit confirmation of the offered location. Declining leaves the resolution session-local and
the run proceeds; a non-interactive or `unattended` run skips the ask-and-persist rungs entirely and
never performs it. Anything beyond the findings artifact and these two is outside the contract.

Executing what a finding recommends belongs to `overengineering:realign`, behind an explicit per-item
human gate. Name it as the next step; never start it unasked.

## Arguments

Parse `$ARGUMENTS`:

- **Layer scope**: one or more values from the layer vocabulary owned by
  `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`; default `all`. A mature repository's surface
  runs past a hundred items and does not fit one context window, so layer-scoped passes are the
  supported way to cover it: they compose because a re-run merges into the same artifact by stable
  finding id. Record exactly the layers walked in the artifact's `scope`. A layer absent from
  `scope` was not walked, which is not the same as walked and found empty, and the merge rules turn
  on that difference.
- **`unattended`** (also accepted as `--unattended`) selects the unattended disposition for
  low-confidence intent (`scrutiny-method` §4): record `OPEN-INTENT`, ask nothing, guess nothing.
  **Attended is the default.** The harness gives a prose skill no reliable probe for whether a human
  is watching, so the caller owns the flag: a dispatched worker, a scheduled lane, or a background
  run passes it. Never infer the mode.
- Anything else is a free-text focus hint, such as a path or a mechanism name. Narrow attention with
  it; it does not change the layer scope, and a hint that matches nothing is reported, not silently
  dropped.

## Before the walk

1. **Resolve the artifact home** by running the whole rung order in
   `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`. Resolve it, never assume the documented
   default's shape. A hardcoded path writes where `realign` never looks. **Then emit the read-only
   opening line**, naming the path just resolved.
2. **Resolve consumer configuration**, meaning protected categories, threshold overrides, the
   observation window, and suppression entries, from the consuming repo's
   `.claude/overengineering.md` through the config-cascade layering. Keys, defaults, per-key merge
   forms, and which layer may weaken what are owned by
   `${CLAUDE_PLUGIN_ROOT}/reference/consumer-config.md`. All layers absent is a valid
   state: the bundled defaults apply and the run says so. When a personal layer materially shapes
   output, name the contributing layer in the report.
3. **Load the prior artifact** if one is there, and hold its statuses for carry-forward. This skill
   writes `Status: OPEN` on a finding it has not seen and carries every other status forward
   verbatim; it never advances, downgrades, or clears one.
4. **Assess evidence availability** per tier (§2) with the probe that established each, including the
   shallow-clone probe above. This leads the report, ahead of any finding, because it changes what
   UNPROVEN means for every row below it (§8).
5. **Set exclusions.** The consumer's own `.claude/overengineering.md` is outside the scan set, so
   recording a judgment does not perturb the next run's inputs.

## The walk

[skills/audit/context/surface-walk.md](context/surface-walk.md) carries the layer-by-layer walk in
the artifact's enum order, with each layer's discovery probes and evidence sources, the custody and
shallow-clone reads, the aggregating-container granularity rule, and the per-layer incremental write.
Read it at the start of the walk, not per layer.

Two properties of the walk matter enough to state here:

- **Write the artifact per layer, as the walk proceeds.** A partial artifact is a checkpoint, not a
  failure: a context-exhausted run then dies with its completed layers persisted and a later pass
  merges into them.
- **Answer the three liveness questions independently for every item** (§3). Inferring one from
  another is what produces every false green the method enumerates.

## Verdicts and evidence

Every verdict is one of the tokens in §6, argued in carry cost (§1), and **cites at least one
empirical source or is classed UNPROVEN naming the tier consulted and whether it was silent or
unavailable** (§2). Documentation, headers, and rationale text are claims to verify, never evidence;
support that stays doc-only is marked unverified in the finding.

Protected items are audited in full and their evidence reported, since §7 caps the *recommendation*,
not the scrutiny. Where protection status is uncertain, §7's tie-break treats the item as protected.
A threshold that fires is cited with its source and its analogical label verbatim (§9); a threshold
the consumer disabled is not cited at all, and the qualitative bar carries the argument instead.

## Intent checkpoints

When intent reconstruction scores MEDIUM or LOW (§4), the disposition is fixed by run mode:

- **Attended (default)**: surface checkpoint questions, with recommendation first, one small
  numbered set, batched rather than drip-fed. When `planning:interview` is installed, reuse its
  question mechanics; when that plugin is absent, ask the same questions inline as a numbered list
  in the response. The fallback is the questions themselves, so nothing is lost but the mechanics.
- **Unattended**: record `OPEN-INTENT` and move on. An invented intent becomes the fence the next
  audit refuses to remove.

"I don't know" is an accepted answer. It routes the item to the empirical track in §8 with its intent
recorded as unrecovered; it is not a failed interview.

## Neighbor routing

This plugin owns the cross-surface retirement verdict and re-implements no neighbor's layer. Every
route below is **presence-gated**: check whether the plugin is installed, and take the inline
fallback when it is not. Record the route and the presence answer in the finding's `Routed-to` field
so a skipped route is visible rather than silent.

| Finding class | Route (presence-gated) | Inline fallback when absent |
|---|---|---|
| The finding is about instruction *text*: a standing instruction that is stale, over-prescriptive, or contradicts another surface | `claude-config:audit-instructions`, when that plugin is installed | Keep the finding in the `agent-instructions` layer with its evidence, and leave the text edit to the operator. Report the wording, do not rewrite it |
| An agent-layer standing-instruction ablation the evidence cannot settle on its own | `claude-config:unhobble`, when that plugin is installed | Route the item to §8's bounded ablation batch instead, at rung 1 of §11's rollback ladder with the observation window and its end date recorded |
| The operator asks what should be *added* rather than what should be retired | `claude-config:audit-automation-gaps`, when that plugin is installed | Say plainly that prospective additions are outside this skill's contract, and record no finding for them. This audit judges incumbents only |
| A plugin's own claims-versus-reality (a component that does not do what its manifest or description says) | `plugin-quality:audit`, when that plugin is installed | Report it as an ordinary liveness finding (§3) on the component and stop there, rather than auditing the plugin's internals |

## Incumbent-first

Before proposing any remediation, search for an owner that already exists: a mechanism in this repo
that covers the concern, a native platform feature that covers it now (with the dated tech-drift
check §5 requires), or a neighbor surface whose contract already holds it. Proposing a new mechanism
to replace an old one, without that search, reproduces the accumulation this audit exists to reverse.
Ownership itself resolves through §12, and ownerless is not a valid terminal state.

## Consumer-agnostic

Nothing here assumes an organization, a repository, a forge, a CI system, a branch name, or an agent
harness. Layers are the ten forge-neutral names in the artifact's vocabulary, and every discovery
probe in the walk resolves what a consumer actually declares.

**Custody is detected, never assumed.** A managed, vendored, or synced file takes one of three
shapes: a copy whose upstream is another repository, a shared workflow this repo only references, or
an organization-level policy. It is identified from the consumer's *own* declarations: a sync
manifest, a code-owners entry, a header the consumer maintains, a documented upstream. Where custody
is upstream, remediation is a delegation (§12), not an in-repo edit, and patching a managed copy
locally creates drift the next sync reverts.

## The report

[skills/audit/context/report-template.md](context/report-template.md) owns the output shape: the
findings artifact as the single source of truth, an inline terminal summary always, and a rendered
HTML view only as a presence-gated extra. Field-level contents, ids, ordering, the spine/prose split,
and merge semantics belong to `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`.

## Gotchas

- **A layer-scoped pass is not a retirement of what it did not look at.** Findings in unwalked layers
  are carried forward untouched and marked not re-evaluated this run.
- **A zero is not a measurement.** For hook-, transform-, and gate-shaped items, no recorded
  invocations is the expected reading for one that works and is heavily used (§5).
- **Two copies, one wired.** Where the same guard exists in a local and a packaged form, the verdict
  must name which copy it is about; the documented rationale often lives with the copy that no longer
  fires.
- **A control used in a comparison gets its own liveness read** before the comparison is admitted
  (§2). A control that never ran contributes a number that measures the refusal to start.
- **Never recommend weakening the practices whose output is the evidence** (§10). Tests, review, type
  checking, and the build are outside this method's scope, and so is the record-keeping that makes
  tiers 1 and 2 readable at all.
