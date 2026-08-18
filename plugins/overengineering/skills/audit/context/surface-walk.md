# Surface walk — the enforcement-surface lane

The lane binding `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` asks for: the item inventory, the
layer vocabulary with its discovery probes, the evidence sources available in this lane, and the
lane's protected-class patterns. This document supplies the first three. The fourth is the method's
own §7 list plus whatever the consumer's configuration adds.

**Nothing here restates the method.** Every bare `§N` below is a section of that method document; a
verdict definition, a threshold number, or a protected pattern written out again in this file would be
a second copy to drift.

The layer order below **is** the artifact's enum order
(`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, "Layer vocabulary"), which is also the
artifact's primary sort key. Walking in it means the artifact is written in sorted order as the walk
proceeds, rather than needing a re-sort at the end.

## Preflight — run once, before layer one

| Probe | Command or read | What it establishes |
|---|---|---|
| Repository presence | `git rev-parse --show-toplevel` | No checkout means nothing to audit; stop before any write |
| **Shallow clone** | `git rev-parse --is-shallow-repository` | `true` makes evidence **tier 2 unavailable**, not silent |
| History depth | `git log --oneline \| wc -l`, and the date of the first commit | Whether history is deep enough to answer "what did this catch" at all |
| Telemetry sink | Any run-record, log, or metrics location the consumer's own configuration or docs declare | Whether tier 1 exists in this consumer at all — **bound the tier-1 read window here**, at walk start, per the artifact contract's self-perturbation rule |
| Incident corpus | Whatever the consumer declares as its incident, post-incident, or decision record | Whether tier 3 exists |
| Custody | Sync manifests, vendor directories, code-owners entries, "generated / managed — do not edit" headers the consumer maintains, references to shared or centrally-owned workflow definitions | Which items are upstream-owned, so remediation is a delegation (§12) rather than an in-repo edit |

**Shallow is not silent.** On a shallow clone, say so in the evidence-availability lead, and make
every UNPROVEN verdict that would have rested on history cite the missing tier by name. An audit that
reports "no history of catches" from a checkout that carries no history is manufacturing a finding.

**Inventory before judgment.** Enumerate a layer's items completely before judging any of them.
Judging as you discover biases the inventory toward whatever the first few items made salient, and it
makes the per-layer write below non-atomic in the only way that matters — a half-judged layer looks
like a fully-judged one.

## The per-layer loop

For each layer in enum order, for each item found:

1. **Identify.** A repo-relative path where one exists; otherwise a kind-prefixed stable identifier
   from the closed prefix set the artifact contract fixes (`protection:`, `app:`, `integration:`,
   and `settings:` for a registration surface outside the repo tree) so it cannot collide with a
   path.
2. **Classify.** Protected category (§7, plus the consumer's configured set)? Intentionally dormant
   (§7)? And its **surface type** — does exercising this item leave a record at all (§5)? Classify
   before reading counts, so a zero is interpreted rather than measured.
3. **Answer the three liveness questions independently** (§3). Record what was read for each. An
   unread question is recorded as unread.
4. **Reconstruct intent** (§4) and record authorship evidence while the history query is open — §12
   needs it and it is expensive to recover later.
5. **Rediscover** (§5): re-solve the reconstructed problem native-first, with the dated tech-drift
   check.
6. **Weigh cost** (§1, §6): carry cost for the keep side; removal, refactor, and testing cost for the
   retire side.
7. **Verdict** (§6), with the protected cap and tie-break (§7) applied last, after the evidence is
   recorded — the cap never removes evidence from the finding.
8. **Owner** (§12).
9. **Write the finding** into the artifact.

## Granularity — aggregating containers, in every layer

An **aggregating container** is an item whose own definition carries a list of independent members: a
hooks manifest registering several entries, a settings scope registering several mechanisms, a lane
whose script or definition names the checks it runs. The rule is cross-layer — stated once here, and
pointed at from the layers where it fires.

- **Container-level by default.** The container is the item, the finding, and the spine row, with its
  members' scripts and any suppression or baseline files cited as its evidence.
- **Per-member sub-verdicts where the member list is mechanical evidence** — that is, where the
  container's *own* definition carries the list. Mechanical, never judgmental. Without them a single
  verdict cannot express "retire member A, keep member B", and clutter concentrates in exactly the
  containers whose members were added one at a time.
- **Never synthesize a member list from reading behavior.** Where the composition is not mechanically
  readable, the container keeps one verdict and the finding says why.
- Either way the container stays **one spine row with one verdict**; members are line-formatted
  entries inside its body, in the shape `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md` fixes
  under "Aggregating containers", with the member claim and anchor it owns.

**The item unit is pinned per layer, not chosen per run.** The unit is part of identity: a different
container derives different ids, and every judgment an operator recorded against the old unit is
orphaned without a word.

| Layer | Container — the item, the finding, the spine row | Members |
|---|---|---|
| `agent-hooks` | the hooks manifest **per plugin or extension**, and each settings scope that registers hooks | the entries it registers |
| `ci-lanes` | the lane | the independent checks the lane's own definition lists |

## Incremental artifact writes

**Write the artifact per layer, as the walk proceeds.** When a layer's items are all judged, merge
that layer's findings into the artifact on disk before starting the next layer, and update `scope` to
name the layers actually completed so far.

- A partial artifact is a **checkpoint**, not a corrupt file. The contract says so explicitly, and the
  re-run merge rules make resuming a re-invocation rather than a recovery procedure.
- A context-exhausted or interrupted run therefore costs only its unwalked layers.
- `scope` is the whole mechanism that makes this safe: a layer absent from `scope` was **not walked**
  and its prior findings are carried forward untouched, while a layer named in `scope` with no
  findings was walked and found empty. Writing a layer into `scope` before its findings are on disk
  inverts that and reads as a retirement of everything in it.
- The memory root's self-ignore guard runs once per session on the first write, per the topic-docs
  binding — not once per layer.

## Layer 1 — `agent-hooks`

Hooks a coding-agent harness runs on its own lifecycle events.

**Discovery probes.** Every settings scope the harness merges, in precedence order, including the
machine-scope and user-scope layers where they are readable; hook definitions shipped by each enabled
plugin or extension; hooks declared in a component's own frontmatter; and any harness-level lever that
switches hooks off wholesale. Enumerate the *registered* set from the live configuration, then the
*present* set from the tree, and diff the two — the difference is where false greens live.

**Evidence sources.** Any run record the harness or the hook itself emits (tier 1); the change that
introduced the hook, its linked issue, and its re-tuning churn (tier 2); the hook's own header and
comments (tier 5, claims only).

**Granularity.** Per the cross-layer rule above, the item is the **hooks manifest per plugin or
extension** — and each settings scope that registers hooks, identified `settings:<path>` where it
lies outside the repo tree — with the entries it registers as its members. Registration files carry
their member lists mechanically, so this layer normally reports per-member sub-verdicts inside the
container's row.

**Layer notes.** A hook script present in the tree but absent from every registration surface is
present-but-unwired — report it as that, not as a hook. A hook registered with a timeout has a third
liveness question with a real answer: whether it completes inside that budget when reached.

## Layer 2 — `agent-instructions`

Standing instruction text loaded into the agent's context by construction rather than on demand.

**Discovery probes.** The repository's own instruction files and rule directories at every scope the
harness loads; output styles or personas the repo ships; the always-loaded portion of each skill,
command, or agent definition the repo owns; and any text a hook injects into context.

**Evidence sources.** Tier 2 for when a line arrived and what it was reacting to; operator attestation
(tier 4) for whether it is still needed; the text itself is tier 5 about its own necessity.

**Layer notes.** This layer is where the neighbor routing in `SKILL.md` fires most often: a finding
about the *wording* of an instruction belongs to the instruction-text neighbor, presence-gated, while
a finding about whether the instruction should exist **at all** is this audit's. Carry the carry-cost
argument (§1): standing instruction text is paid every session whether or not it ever fires.

## Layer 3 — `repo-hooks`

Repository-declared lifecycle automation that is not version-control-triggered: task-runner and
package-manager lifecycle scripts, build-tool pre- and post-steps, format- or lint-on-save
enforcement the repo declares, container or workspace bootstrap steps.

**Discovery probes.** The repo's manifest and task-runner definitions; any lifecycle-script keys those
manifests support; workspace and container definition files; editor-configuration the repo tracks.

**Evidence sources.** Tier 2 on introduction and churn; the build or task logs where the consumer
keeps them (tier 1); operator attestation for anything that only manifests on a developer machine
(tier 4, recorded with its date and speaker, never promoted to a measurement).

**Layer notes.** Machine-local behavior is the standing evidence gap in this layer. Record it as
attestation, and do not upgrade an anecdote to a firing count.

## Layer 4 — `vcs-hooks`

Version-control hooks: what is installed at the effective hooks path, what the repo tracks as hook
sources, and any hook-manager manifest that installs them.

**Discovery probes.** The configured hooks path (it is configurable and frequently redirected); the
contents of that path; the tracked hook sources in the repo; the hook-manager manifest where one
exists; and whether the manifest's declared set matches what is installed.

**Evidence sources.** Tier 2 for introduction and churn; whatever the hook writes when it blocks
(tier 1) — usually nothing, which is §5's trap, not a measurement; the bypass rate where the consumer
records it.

**Layer notes.** Manifest-declared and actually-installed are two different sets, and a developer who
has never run the installer has neither. Answer wiring from the installed state, never from the
manifest's claim about it.

## Layer 5 — `ci-lanes`

Pipeline jobs, workflows, and stages the consumer's CI system runs.

**Discovery probes.** Every pipeline definition file the CI system reads; the triggers, path filters,
and conditions on each; whether the lane is required by anything downstream; reusable or shared
definitions the repo only references (custody — see preflight); and the recent run history where the
CI system exposes it.

**Evidence sources.** Run history with outcomes and durations (tier 1, usually the richest tier
available in this layer); tier 2 for what a lane was added in response to; the lane's own name and
comments (tier 5).

**Granularity.** Per the cross-layer rule above, the container for this layer is the **lane** and its
members are the independent checks the lane's own script or definition lists. Lane-level by default;
per-member sub-verdicts inside the lane's own finding where that list is mechanically readable, and
one lane verdict with a stated reason where it is not.

**A lane nothing keys on.** A lane that runs and reports but whose result is not required by any
aggregate, branch rule, or downstream step changes no outcome. That is a §3 false green, not a
DOWNGRADE candidate discovered by taste.

## Layer 6 — `gate-scripts`

The check implementations a lane or hook invokes: the scripts, their fixtures, and the suppression,
baseline, or allowlist files that shape what they report.

**Discovery probes.** Every script a lane or hook actually calls (resolved from the caller, not from a
directory listing — an uncalled script in the same directory is its own finding); each script's own
mode flags; suppression, baseline, and allowlist files and their growth over time; each script's
self-test where one exists.

**Evidence sources.** The script's own findings history in CI logs (tier 1); tier 2 for the change
that added each rule and each suppression; the suppression file itself is evidence of the
false-positive tax the script levies (§1).

**Layer notes.** A growing suppression file is carry cost made visible — read its growth rather than
its size. A script that no caller invokes is a present-but-unwired finding, and it is one of the
cheapest real retirements on the whole surface.

## Layer 7 — `satellite-workflows`

Automation that is not a gate: schedulers, bots, labelers, stale-item sweepers, release and publishing
automation, notification and report-posting workflows.

**Discovery probes.** Scheduled and event-triggered definitions that gate nothing; automation
configuration files the forge or a bot reads; anything that posts, labels, closes, or notifies.

**Evidence sources.** The record of what it actually did — comments posted, items closed, releases
cut (tier 1, usually readable); tier 2 for when it was introduced; and the human response to its
output, which is the honest measure of a notification's value.

**Layer notes.** Ewaschuk's cost mechanism is the one that transfers here (§9): a noisy surface is
ignored wholesale, so a notification nobody acts on is not neutral — it degrades the attention every
other notification depends on. That is an argument, not a threshold; cite §9's qualitative bar rather
than a number.

## Layer 8 — `branch-protection`

Rules the forge enforces on refs: required checks, required reviews, restrictions, rulesets.

**Discovery probes, in order.**

1. **A forge API, presence-gated** — a forge MCP server or CLI, when one is configured and
   authenticated in this environment. Read the effective rules for the refs the repo actually uses.
2. **Policy-as-code in the repo**, when the consumer manages its protections declaratively — that
   file is a first-class read and is often the only readable source.
3. **Neither available** — emit the rows anyway, as **unreadable**: the item is identified
   (`protection:<rule-name>` where a name is known, or one row naming the ref pattern), the verdict is
   `UNPROVEN` naming the tier as *unavailable* rather than silent, and intent is `OPEN-INTENT`. Never
   infer a protection rule from the presence of a lane that looks required.

**Evidence sources.** The effective rule set (tier 1 for what is enforced right now); tier 2 where
protections are managed as code; operator attestation (tier 4) for why a rule was added.

**Layer notes.** This layer is out-of-repo by construction unless the consumer manages it as code, so
remediation is a delegation (§12) with `DELEGATED-EXTERNAL` and a pointer, and the finding says which
of the three probes above produced it.

## Layer 9 — `forge-apps`

Installed applications, bots, and marketplace integrations that act on the repository.

**Discovery probes.** The forge API where it is available (same presence gate as layer 8);
configuration files an app reads from the repo, which are the readable shadow of an app whose
installation cannot be listed; the traces apps leave — status entries, comments, commits, labels.

**Evidence sources.** The traces themselves (tier 1); tier 2 for when the configuration arrived;
tier 5 for any doc claiming an app is in use.

**Layer notes.** An app whose configuration file is present and whose traces stopped is a strong
liveness finding. Where the installation itself is unreadable, the row is unreadable in the same shape
as layer 8's — identified, `UNPROVEN` on an unavailable tier, never guessed at.

## Layer 10 — `external-integrations`

Third-party services the repository declares a dependency on for enforcement or reporting: status
reporters, coverage and quality services, security dashboards, chat notifications, policy services.

**Discovery probes.** Service configuration files the repo tracks; credentials or token *names*
referenced by lanes and hooks (never their values); badges, links, and required status names that only
one external service can satisfy; declared webhooks.

**Evidence sources.** The service's own reported activity where it is readable (tier 1); tier 2 for
the integration's introduction; operator attestation for whether anyone reads it (tier 4).

**Layer notes.** Credential-shaped values are never read, echoed, or carried into a finding — the name
of the secret is the evidence, its value never is. An integration nobody reads still costs a
credential to rotate and a service to trust, and that is the carry-cost argument to make.

## Closing the walk

- Reconcile against the prior artifact by stable id per the contract's merge rules: carry statuses
  forward, recompute verdicts, record `## Closed since last run` rows for prior findings whose layer
  was walked and whose item is gone, and surface any verdict that changed direction underneath a
  judgment the operator already made.
- Report suppressed findings and every suppression entry that did **not** suppress, per the contract.
- Rank the UNPROVEN residue by carry cost and propose the bounded ablation batch (§8) — one batch,
  owner and re-check date per item, protected and intentionally-dormant items excluded.
- Then hand off to [report-template.md](report-template.md) for the output shape.
