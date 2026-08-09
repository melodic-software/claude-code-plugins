# docker-sandbox-substrate

## Brief

### TLDR

Docker Sandboxes (`sbx`) was evaluated as an isolation substrate and as a possible route to an
agent-agnostic autonomous pipeline. It is a **substrate instance for a seam this repository already
specifies** — not a plugin, not a new repository, and not a framework. Integrating it costs **zero
files here**, because the guided-setup path already ships and the ladder forbids naming a product
instance in this repository at all. It was probed live on Windows 11 Pro under a hardened invocation
and **both isolation assertions failed inside the boundary**, which is the passing condition.

The larger goal that emerged — running the full delivery lanes as separate autonomous runs — is
governed by one evidence finding that reshapes it: **verifier independence pays at the model level,
not merely the context level**, and **judge diversity outranks judge size**. Verification topology
becomes a configurable column on the existing guardrail matrix, keyed on roles and relations rather
than on capability labels, which do not survive a model release.

### Goal

Decide whether and how to adopt a kernel-separated local isolation substrate, and fix the shape of the
verification topology for an autonomous multi-run delivery pipeline — both grounded in current
authoritative sources rather than recall, and both expressed so that no vendor name enters this
repository's contract surface.

### Constraints

- **Instance names never enter this repository.** `guardrails/isolation-ladder.md` names substrate
  CLASSES as marked examples only; the instance id has exactly one home — the `substrate` field in a
  consumer's security binding, outside this repo.
- **Trust is earned by demonstrated boundary behavior**, never by licence, audit history, or version
  number. The contract is deliberately silent on provenance and treats it as an org choice.
- **A policy the governed agents can lower is no policy.** Verification floors live on the
  agent-unwritable security binding, as the per-item caps already do.
- **Independent aggregation, never deliberation.** Consensus-by-discussion measured worse than every
  single-model baseline; this is a fixed invariant of the design, not a configurable knob.
- **The runner stays trigger-gated.** Nothing here fires a T4 build trigger; an off-the-shelf substrate
  scales the platform wall rather than supplying the case for building past it.
- Fresh-docs mandate applies to every contract-surface change, per `CLAUDE.md`.

### Acceptance criteria

1. `Docker.sbx` is tracked in the dotfiles user-scope winget list, and `provisioning` is unchanged —
   satisfied by `melodic-software/dotfiles#427`; the WHP optional feature proved unnecessary on a host
   with Hyper-V already enabled.
2. A probe transcript exists showing **both** ladder assertions failing inside the boundary under
   `--clone` + `deny-all`, with the outer context proving each target reachable/present first, and
   `outer_context_networked: true` — satisfied by `.work/docker-sandbox-substrate/probe-evidence-sbx-l3.md`.
3. The isolation probe gains a **third assertion covering the workspace mount**, and its egress
   assertion tests whether **data flows** rather than whether `connect()` fails.
4. Verification policy is expressed as roles + relational constraints + machine-checkable predicates,
   with **no capability label** (`frontier`, `flagship`, `daily driver`) anywhere in it.
5. Per-class verification **floors** (minimum checker count, whether cross-vendor is required) live on
   the security binding; lens selection and the advisory lane live in plugin `userConfig`.
6. The visual E2E lane is wired as **advisory only**, downstream of deterministic detection, and cannot
   block.
7. Merge remains human-gated, with additional routing on implementer/checker disagreement; anything
   auto-proceeding requires **unanimous** checker agreement.

### Captured assumptions

- `sbx` evidence is **version-bound** to `v0.38.0`. The product ships roughly every two weeks with an
  actively changing security surface, so the probe result is a snapshot, not a standing property.
- The probe covered one kit (`shell`), one workspace, one host. The **default (non-clone) mode was not
  probed** — Docker documents it as having no workspace isolation, so it is assumed to fail.
- `local-policy`'s `filesystem:read/write allow **` is assumed to govern what the host permits `sbx` to
  mount, not what the guest can reach; the guest saw only the read-only workspace. Not probed directly.
- The pipeline-architecture evidence transfers from math/QA benchmarks to software delivery. The lane
  flagged this as its central limitation; the software-specific evidence is thinner and newer.
- Most multi-agent papers do not run the compute-matched baseline (a five-stage pipeline versus one run
  with five times the thinking budget), so measured gains are confounded by scaffold quality.

### Out-of-scope

- **A new repository or framework.** `sbx` scores agent-agnostic but is welded to Docker's own microVM
  and is proprietary — a provider candidate, never a framework competitor. The prior peer-frameworks
  verdict (compose, do not adopt wholesale) stands.
- **Building the runner.** Its design pack is complete and its build triggers are unfired.
- **Adopting an orchestrator now.** Neither agent-native option ships a gate, which is the part the
  design most needs; the pipeline stays thin code against a provider seam so the choice stays
  reversible.
- **Naming `sbx`, Multipass, Hyper-V, or any product in this repository's contract surface.**

### Deferred questions

- **Q20 — What exact form should the probe's workspace assertion take, and how should the egress
  assertion be reworded to test data flow rather than `connect()` failure?** *(arbiter:
  `/planning:plan`)* A connect-only probe grades this substrate wrongly: raw TCP `connect()` succeeds
  because the interception layer accepts the SYN and then drops the session.
- **Q21 — Should the isolation ladder model kit-supplied allow rules?** *(arbiter: USER-RESERVED)* The
  `shell` kit added `network allow openrouter.ai` on top of a global `deny-all`. Installing a kit can
  widen egress; the ladder does not currently model this, and it is a supply-chain concern that
  changes what a level binding certifies.
- **Q22 — Should the three genuinely-additive "software factory" concepts be recorded as deferred
  items with triggers?** *(arbiter: USER-RESERVED)* Accepted in principle (Q11); the trigger wording is
  unwritten. They are fleet-level economics as tracked output (partly covered by the telemetry and
  return-accounting contracts), portfolio-scale multi-repo fan-out as a unit of work (absent — the
  seams are per-run), and self-service golden paths for humans and agents (absent).
- **Q23 — What re-verification cadence applies to version-bound substrate evidence?** *(arbiter:
  USER-RESERVED)* A ~2-week release cadence with three security fixes in three weeks means specific
  flags, defaults, and guarantees rot; the durable findings are the architecture and the posture.

## Plan

### Goal

**What**: harden the isolation probe so it measures data flow and the workspace mount, then express
verification topology as a configurable column on the existing guardrail matrix — floors on the
agent-unwritable security binding, lens selection and the advisory visual lane in plugin
`userConfig`, merge human-gated with disagreement routing.

**Why**: the probe currently certifies `L2` while the whole host-execution attack class goes
unmeasured, and a connect-only egress test grades a microVM-class substrate wrongly. The pipeline
half of the Brief is decided but unbuilt: without a topology column, verifier count, model routing,
and lens diversity have nowhere to bind.

### Standards grounding

No standards index is present in this repository, so the ladder's absent-index inference applies.
Grounded on the ambient repository standards; nothing was fetched beyond them.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| Plugin contract surface | `CLAUDE.md` — Fresh-docs mandate; Design rules (repo-agnostic, configurable without editing the plugin, plugin-form-safe, versioned) | team |
| Branch / PR process | `CLAUDE.md` — Branching & PRs (`pr-issue-linkage` body contract); `AGENTS.md` — stage explicit paths | team |
| Contract-slice lifecycle | `docs/conventions/topic-docs/README.md` — slice pruned before merge (`contract-slice-prune-gate`) | team |
| Plugin acceptance | `docs/MIGRATION-PLAYBOOK.md`, `docs/PLUGIN-PHILOSOPHY.md` | team |

Offer, not applied: persist a standards index so future plans resolve these surfaces deterministically
instead of inferring them.

### Q20 — RESOLVED (this plan is its arbiter)

Both halves resolve as a **rewording plus one additive assertion**, not a loosening of any existing
check.

**Egress — test data flow, not `connect()`.** The probe becomes a *certificate-verified* TLS fetch of
`<well-known-external-host>`. Certificate verification is what converts the two observed false
negatives into true negatives: an interception layer that accepts the SYN and drops the session
cannot complete the handshake, and a policy block page cannot present a certificate valid for the
probed host. The existing non-zero-exit invariant therefore stands unchanged — no relaxation — and
the transcript additionally records HOW denial occurred, in the per-target comma-separated form
`credentials_absent` already uses:

- `egress_denied.transport_outcome` ∈ `dns-unresolved` | `connect-failed` | `tls-failed` |
  `policy-intercepted`, one entry per probed host, positionally paired with `host`.
- A completed, host-authenticated TLS session that read origin application data is the FAIL
  condition; it has no passing token, so it cannot be recorded as a pass.

**Workspace — containment proven from the OUTER side.** A third assertion, `workspace_contained`,
asserting that **no write performed inside the boundary becomes visible at the host workspace path**.
Verifying from outside is what makes one rule cover both substrate shapes: a read-only mount fails
the inner write, a clone-mode mount accepts it invisibly, and both are contained. The inner exit code
is therefore deliberately NOT constrained — only host state is.

Legs, in order:

1. Outer, pre: the marker path is absent at the host workspace root; record the exit as
   `host_pre_absent: "0"`. Record `git_config_digest_pre` (the literal `absent` where the workspace
   has no `.git/config`).
2. Inner: write the marker into the workspace mount, and append to `.git/config`. Record
   `inner_exit_code` for the record only.
3. Outer, post: the marker is still absent (`host_post_absent: "0"`) and
   `git_config_digest_post` equals `git_config_digest_pre`.

`.git/config` is named explicitly because it is a command key ring — `core.fsmonitor` executes host
code on `git status` — so a workspace assertion that only checked ordinary files would miss the
documented escalation path.

### Approach

Phase order is dependency-driven: the vocabulary leaf (Phase 2) must exist before any surface can
cite it, and Phase 1 is independent of every other phase.

#### Phase 1: Probe hardening — data-flow egress + workspace containment [TODO]

Review: security

Criterion 3. Delivers the Q20 resolution above.

- [ ] **Pre-flight consumer check** (FIRST work item — this migrates the probe-transcript contract):
      `Grep` for `egress_denied`, `credentials_absent`, `outer_context_networked`, and
      `verifyProbeTranscript` across `plugins/`, `scripts/`, and `.github/`; document every parse
      path. Known consumers at plan time: `scripts/check-security-binding.mjs`,
      `scripts/check-security-binding.fixtures.test.mjs`, the fixtures manifest, and
      `skills/setup/SKILL.md`'s guardrail slice.
- [ ] `templates/isolation-probe.md` — reword the egress assertion to the certificate-verified TLS
      form; add the `workspace_contained` assertion, its outer-first probe shape, and its per-substrate
      wrapping note; extend the transcript capture shape with both new blocks.
- [ ] `reference/guardrails/isolation-ladder.md` — the `L2` level text names default-deny egress and
      credential protection; add workspace containment as the third property a boundary must
      demonstrate. Classes only, no instance names.
- [ ] `scripts/check-security-binding.mjs` — extend `verifyProbeTranscript`: validate
      `egress_denied.transport_outcome` (closed token set, one entry per host, positionally paired)
      and the `workspace_contained` block. **The `workspace_contained` check runs LAST in the
      function** — the ~50 negative transcripts have `findings_substrings` pinned to their own
      rejection reason, and an earlier-running new check would rewrite all of them.
- [ ] Transcripts referenced by PASSING fixtures gain both new blocks — exactly 6 JSON files:
      `ci-pool-a-l2.json`, `ci-pool-a-l2-as112-v6.json`, `ci-pool-a-l2-multi-host.json`,
      `ci-pool-a-l2-id-rsa.json`, `ci-pool-a-l3.json`, `ci-pool-a-l3-hosted.json`
      (`ci-pool-a-l1-2026-07-01.txt` is an `L1` reference and is not verified).
- [ ] New NEGATIVE transcripts + manifest cases: missing `workspace_contained`; marker visible on the
      host post-write; `git_config_digest` changed; missing `transport_outcome`; count mismatch
      against `host`; a `data-flowed` egress outcome.
- [ ] `skills/setup/SKILL.md` — the guardrail slice's probe narration gains the third assertion.

**Sanity Check:**

- `node scripts/check-security-binding.fixtures.test.mjs` exits 0 with every pre-existing case's
  `findings_substrings` unchanged (diff the manifest: only ADDED keys, no MODIFIED `findings_substrings`
  on pre-existing cases).
- `grep -c "workspace_contained" plugins/autonomy/skills/setup/templates/isolation-probe.md` ≥ 3.
- `grep -n "must fail to CONNECT" plugins/autonomy/skills/setup/templates/isolation-probe.md`
  returns empty.
- `grep -rn "sbx\|Docker Sandboxes\|Multipass\|Hyper-V" plugins/autonomy/` returns empty.

#### Phase 2: Verification-topology contract leaf + matrix column [TODO]

Review: architecture

Criterion 4, and the vocabulary Phases 3–5 cite. Documentation only — no schema, no code.

- [ ] `reference/guardrails/verification-topology.md` (CREATE) — the normative leaf. Fixes the Q17
      vocabulary and nothing else:
      **roles** `generator` · `checker` · `cross_vendor_checker` · `ranker`;
      **relations** `distinct_model_from` · `distinct_vendor_from` · `not_weaker_than` (present but
      NOT defaulted — no cross-vendor capability ordering exists to evaluate it against);
      **predicates** `min_context_tokens` · `requires_modality` · `requires_feature`;
      **budget** cost ceilings; **pin** `pinned_model_id`, append-only, reproducibility of a recorded
      measurement only.
      Records `frontier`, `flagship`, and `daily driver` as REJECTED with their sourced reasons, in the
      same shape the ladder records its rejected trigger-source axis.
      States the two fixed invariants: **independent aggregation, never deliberation**, and
      **unanimous checker agreement for anything auto-proceeding**.
- [ ] `reference/guardrails.md` — add the **Verification topology** column to the matrix, its
      one-line column definition, and a glance-layer routing row to the new leaf. Depth stays in the
      leaf; the hub gains no prose beyond the row.

**Sanity Check:**

- `grep -rn "frontier\|flagship\|daily driver" plugins/autonomy/reference/` matches ONLY inside the
  leaf's rejected-vocabulary section.
- `plugins/autonomy/reference/guardrails.md` matrix header row contains `Verification topology`, and
  the glance-layer table contains a row pointing at `guardrails/verification-topology.md`.
- Every plugin-internal link in the new leaf resolves (`skill-reference-verify` hook passes).

#### Phase 3: Per-class verification floors on the security binding [TODO]

Review: security

Criterion 5, binding half.

- [ ] **Pre-flight consumer check** (FIRST work item): `Grep` for `verification_blocking`,
      `merge_policy`, and `schema_version` parse sites across the plugin and repo scripts.
- [ ] `schemas/guardrails-security-binding.schema.json` — add `verification_topology` as an
      OPTIONAL top-level key: per class, `min_checkers` (integer ≥ 1) and `cross_vendor_required`
      (boolean). Optional-with-contract-defaults follows the `escalation_severity` precedent, so
      `schema_version` stays `"1.0"` and all 113 existing fixtures continue to validate. Absent
      binding is NOT a hole: the leaf's shipped floors apply, exactly as `escalation_severity` falls
      back to contract defaults.
- [ ] `scripts/check-security-binding.mjs` — floors are FLOORS: tightening legal, weakening below the
      shipped default invalid, no `override_justification` escape (the same rule
      `verification_blocking` already carries).
- [ ] New fixtures: a valid tightened binding; a weakened `min_checkers`; a `cross_vendor_required`
      dropped below its floor; a non-class key.

**Sanity Check:**

- `grep -c '"schema_version": { "const": "1.0" }' plugins/autonomy/skills/setup/schemas/guardrails-security-binding.schema.json`
  returns 1 (the version did NOT move).
- `node scripts/check-security-binding.fixtures.test.mjs` exits 0; the 22 pre-existing exit-0 cases
  still exit 0 unmodified.

#### Phase 4: Plugin `userConfig` — lens selection and the advisory visual lane [TODO]

Review: code-design

Criterion 5 (`userConfig` half) and criterion 6.

- [ ] **Fresh-docs gate** (FIRST work item, non-negotiable — this is a plugin-manifest contract
      change): open `docs/OFFICIAL-DOCS.md`, WebFetch
      <https://code.claude.com/docs/en/plugins-reference> for the current `userConfig` schema and
      `${user_config.KEY}` substitution rules, and cite the URL in the commit. No key is written
      before that fetch.
- [ ] `.claude-plugin/plugin.json` — additive keys for lens selection and the advisory lane, each with
      an explicit `default` (the plugin's existing keys all carry one).
- [ ] The visual lane is wired so it **has no blocking knob at all** — structurally incapable of
      gating rather than defaulted-off-and-promotable. It is placed downstream of deterministic
      detection and narrates what the deterministic layer already found.
- [ ] `reference/guardrails/verification-topology.md` — document the split: floors on the binding,
      lens selection and the advisory lane in `userConfig`. Agents may raise their own verification,
      never lower it.
- [ ] `skills/setup/SKILL.md` + `CHANGELOG.md` + `version` bump.

**Sanity Check:**

- `grep -n "advisory" plugins/autonomy/reference/guardrails/verification-topology.md` shows the visual
  lane with NO `blocking` token anywhere in its section.
- `node -e "JSON.parse(require('fs').readFileSync('plugins/autonomy/.claude-plugin/plugin.json'))"`
  exits 0 and every new `userConfig` entry has a `default`.
- The commit message cites the fetched docs URL.

#### Phase 5: Merge gating and disagreement routing [TODO]

Review: security

Criterion 7.

- [ ] Confirm — do not assume — that implementer/checker disagreement IS the existing
      `verification-divergence` escalation event class ("a verification outcome diverges from the
      expected or claimed result"). If it is, bind to it and invent no token; if it is not, the new
      class binds additively as an OPTIONAL `escalation_routes` key, following the `runner-*`
      precedent.
- [ ] `reference/guardrails.md` — merge-policy column keeps human merge; record that any
      auto-proceeding path additionally requires unanimous checker agreement.
- [ ] `reference/guardrails/work-classes.md` — the unanimity requirement joins the promotion
      discipline: a promoted `C2`/`C3` auto-merge cell still does not auto-proceed on checker dissent.
- [ ] `scripts/check-security-binding.mjs` + fixtures — a binding whose `merge_policy` is `auto` for a
      class whose `verification_topology` floor cannot express unanimity is invalid.

**Sanity Check:**

- `grep -n "unanimous" plugins/autonomy/reference/guardrails.md plugins/autonomy/reference/guardrails/work-classes.md`
  returns a match in both.
- `node scripts/check-security-binding.fixtures.test.mjs` exits 0 with the new dissent fixtures.

#### Phase 6: Close-out [TODO]

- [ ] Prune `docs/topics/docker-sandbox-substrate/` in the final commit before merge
      (`contract-slice-prune-gate` is a required check — a PR landing the slice on `main` can never go
      green).
- [ ] Paste the approved PLAN into the PR body inside a `<details>` block.
- [ ] Comment the outcome on issue #2110 and close the items it lists that this work discharges.

**Sanity Check:** `git show --stat HEAD -- docs/topics/` shows only deletions; `gh pr view --json body`
contains the PLAN block, a closing keyword, and a non-empty `## Related` section.

### Files Affected

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/skills/setup/templates/isolation-probe.md` | Modify | Data-flow egress rewording; third assertion; transcript shape |
| `plugins/autonomy/reference/guardrails/isolation-ladder.md` | Modify | `L2` gains workspace containment as a demonstrated property |
| `plugins/autonomy/reference/guardrails/verification-topology.md` | Create | The Q17 vocabulary leaf and its two fixed invariants |
| `plugins/autonomy/reference/guardrails.md` | Modify | Verification-topology column, definition, routing row, unanimity note |
| `plugins/autonomy/reference/guardrails/work-classes.md` | Modify | Unanimity joins the promotion discipline |
| `plugins/autonomy/skills/setup/schemas/guardrails-security-binding.schema.json` | Modify | Optional `verification_topology` floors |
| `plugins/autonomy/skills/setup/scripts/check-security-binding.mjs` | Modify | Transcript checks; floor checks; unanimity check |
| `.../evals/fixtures/security-binding/probe-transcripts/*.json` (6) | Modify | Both new assertion blocks |
| `.../evals/fixtures/security-binding/*.json` + manifest | Create | New negative and tightened-binding cases |
| `plugins/autonomy/.claude-plugin/plugin.json` | Modify | `userConfig` keys; `version` bump |
| `plugins/autonomy/skills/setup/SKILL.md` | Modify | Probe narration; topology setup |
| `plugins/autonomy/CHANGELOG.md` | Modify | Entries per phase-PR |

### Alternatives Considered

| Alternative | Why rejected |
|---|---|
| Bump `schema_version` to `2.0` for the new keys | Invalidates every adopting org's binding, which fail-closes their autonomous dispatch until re-authored. The schema's own `runner-*` and `escalation_severity` keys establish optional-additive as the house pattern |
| Make the third assertion optional-when-absent | A binding could keep certifying `L2` on two-assertion evidence — the silent degrade the ladder explicitly forbids. It rides the existing UNPROVEN path instead: the binding stays valid, the level stops counting toward eligibility |
| Assert workspace containment by requiring the inner write to FAIL | Grades clone-mode substrates wrongly — they legitimately accept the write and discard it. Verifying host state from the outer side covers both shapes with one rule |
| Relax `exit_code` to allow `0` with a `policy-intercepted` outcome | Loosens a currently-strict invariant on evidence an executing agent could doctor. Certificate verification achieves the same discrimination while keeping non-zero required |
| A new escalation mechanism for checker disagreement | `verification-divergence` already exists, is already required in `escalation_routes`, and already means this. Phase 5 confirms before binding |
| Model the visual lane as a `security-review.md` layer with `blocking` defaulted off | A defaulted-off knob is promotable; measured 70% judge precision with a consistent over-crediting direction means it must never become a gate. No knob is the stronger form |

### Test Strategy

Test-first throughout — the fixture harness is already the red-green loop for this surface.

- **Phase 1, 3, 5 (checker changes):** write the failing fixture FIRST (new negative transcript +
  manifest case with its expected `findings_substrings`), confirm
  `check-security-binding.fixtures.test.mjs` fails on it, then implement the check. This is the
  established pattern for all 113 existing cases.
- **Regression floor:** the 22 pre-existing exit-0 fixtures must still exit 0, and no pre-existing
  case's `findings_substrings` may change. That single assertion is what catches the check-ordering
  hazard in Phase 1.
- **Phase 2 (docs only):** verification is the repo's own link and reference hooks plus the
  vendor-name greps in the phase Sanity Check; no unit test applies.
- **Phase 4:** JSON parse plus a `default`-presence assertion on every new `userConfig` key; the
  fresh-docs citation is verified by reading the commit message.
- **Not covered by any test:** whether the reworded egress assertion actually discriminates on a real
  substrate. The existing probe evidence is the only empirical datum, and it is version-bound. Re-running
  the probe against the hardened recipe is the honest verification and is called out as a risk below.

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The new transcript check runs before existing checks and rewrites ~50 pinned `findings_substrings` | High | Med | Ordering is a stated implementation constraint; the "no pre-existing substring changed" assertion catches it mechanically |
| Certificate verification is defeated where an org installs the interceptor's CA inside the boundary | Med | High | That configuration is itself a finding; the leaf states it explicitly rather than leaving it implicit |
| Shipped floor VALUES are unevidenced | High | Med | OPEN DECISION below — not decided by this plan |
| The hardened recipe is never re-run against a real substrate, so the rewording is untested in practice | Med | Med | Re-probe is cheap (`probe-l3` still exists, stopped); recommended before Phase 1 merges |
| Pipeline evidence is pre-consensus and several findings are single-study | High | Med | `/planning:devils-advocate` at Step 4; the leaf records the evidence basis so a later result can demote a choice rather than silently contradicting it |
| Scope creep from Q21 into Phase 1 | Med | Med | Q21 is USER-RESERVED; no phase depends on it. If a phase starts to, that is drift and stops |

### OPEN DECISIONS — not resolved by this plan

1. **Shipped per-class floor values** (`min_checkers`, `cross_vendor_required`). The interview fixed
   the SHAPE, never the numbers, and no evidence in the lanes sets them. RECOMMENDED starting floors:
   `C1` 1/no · `C2` 1/no · `C3` 2/no · `C4` 3/yes · `C5` 3/yes — floors, so an org may only tighten.
2. **PR granularity.** RECOMMENDED: Phase 1 ships as its own PR (self-contained, security-bearing,
   independently revertable); Phases 2–5 ship as a second PR carrying the whole topology change
   coherently. Alternative: one PR per phase, five review round-trips.

### Blast radius

**HIGH.** The change touches an agent-unwritable security surface, a fail-closed checker with 113
gated fixture cases, the isolation ladder's definition of `L2`, and a plugin manifest consumers
install. Triggers matched: security-sensitive surface; contract migration with downstream consumers;
fail-closed policy semantics.

