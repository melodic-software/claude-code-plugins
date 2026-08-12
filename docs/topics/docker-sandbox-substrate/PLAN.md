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

**Egress — test data flow, not `connect()`.** The probe becomes a TLS fetch whose passing condition is
that **the inner peer is not the origin, or no origin bytes were read**. Certificate verification alone
was the first draft and is NOT sufficient: an org that installs a TLS-inspection CA inside the boundary
makes the interceptor's certificate verify cleanly, which would grade a fully-intercepted boundary as
egress-capable in one direction and a legitimately-denied one as passing in the other. The
discriminator is therefore a **peer-certificate comparison against the outer context**, which needs no
trusted-CA assumption at all:

- The outer probe records the peer certificate fingerprint of each reachable target.
- The inner probe records its own. Denial is proven when the handshake fails, or when the inner
  fingerprint DIFFERS from the outer one (an interceptor, not the origin), with zero origin bytes read.
- `egress_denied.transport_outcome` ∈ `dns-unresolved` | `connect-failed` | `tls-failed` |
  `peer-substituted` | `not-applicable`, one entry per probed host, positionally paired with `host`,
  in the comma-separated form `credentials_absent` already uses.
- A completed handshake whose peer fingerprint MATCHES the outer one and from which application data
  was read is the FAIL condition. It has no passing token, so it cannot be recorded as a pass.

Three additional legs close gaps a single-target exit-code test leaves open:

- **Client readiness.** A boundary with no working TLS client would otherwise "pass" trivially — a
  missing tool is indistinguishable from a denied network. The same client must first succeed against
  an in-boundary endpoint; a client that cannot be shown to run yields UNPROVEN, never a pass.
- **Multiple targets under different operators.** One denied destination does not establish
  default-deny: a policy can allow specific hosts while denying the probed one. At least two DISTINCT
  external targets are required, each independently proven reachable from the outer context.

  *Scope change, 2026-08-10, found at implementation.* ~~one of them a randomized name no allowlist
  could have anticipated~~ — a randomized name cannot satisfy the recipe's existing outer-reachability
  invariant (`outer_exit_code` must be `"0"`, because a target that fails everywhere "fails" inside too
  and proves nothing). Unguessability and outer-reachability are mutually exclusive over DNS, and
  outer-reachability is the older, load-bearing rule. Distinct operators is the nearest property that
  survives it.
- **Address family recorded, never inferred.** IPv4 and IPv6 are probed and recorded separately; an
  absent family is `not-applicable`, never counted as denied.

**Workspace — host-write containment, proven from the OUTER side.** A third assertion named
`workspace_host_write_contained` — the longer name is deliberate, because the short form would
overclaim. It asserts that **no write performed inside the boundary becomes visible at the host
workspace path**, which is Q6's write-back scope, and it does NOT cover read exposure (see the named
limitation below). Verifying from outside is what makes one rule cover both substrate shapes: a
read-only mount fails the inner write, a clone-mode mount accepts it invisibly, and both are
contained. The inner exit code is deliberately NOT constrained — only host state is.

Legs, in order:

1. Outer, pre: snapshot the host workspace. Record `git_config_digest_pre` (the literal `absent`
   where the workspace has no `.git/config`) and confirm every canary path is absent.
2. Inner: write a **randomized canary** at each of a small fixed set of shapes — a plain file, a
   dotfile, and a `.git/`-relative path — and append to `.git/config`. Randomized names defeat a
   substrate that special-cases a known probe path; the shape set covers case-folding and
   hidden-file handling that a single literal path would miss. Record `inner_exit_code` for the
   record only.
3. **Tear the boundary down, then** re-check. An immediate post-check can miss delayed propagation
   on a caching or asynchronously-flushed mount, so the post-check runs after teardown, with paths
   canonicalized on both sides before comparison.
4. Outer, post: every canary still absent (`host_post_absent: "0"`) and `git_config_digest_post`
   equals `git_config_digest_pre`.

`.git/config` is named explicitly because it is a command key ring — `core.fsmonitor` executes host
code on `git status` — so an assertion that only checked ordinary files would miss the documented
escalation path.

**Where the host workspace path is not observable from the outer context** (a hosted ephemeral
executor whose storage the operator cannot inspect), the assertion records `not-applicable` and the
level is UNPROVEN for that surface. It never silently passes.

**Named limitation, carried into the leaf, not hidden.** This assertion does not measure READ
exposure, and clone mode leaves reads fully open — so exfiltration of workspace contents is
unaffected by a passing result. Q6 scoped the assertion to write-back; widening it to reads is
recorded as a deferred item with its own trigger rather than implied by the assertion's name.

### Approach

Phase order is dependency-driven: the vocabulary leaf (Phase 2) must exist before any surface can
cite it, and Phase 1 is independent of every other phase.

#### Phase 1: Probe hardening — data-flow egress + workspace host-write containment [DONE]

**SHIPPED.** PR #2150 merged as `c1b4c629`; `autonomy` is at `0.15.0` on `main`. 34/34 checks,
11/11 review threads resolved, 474 fixture checks, 0 pre-existing pinned reasons changed.

**Merge gate satisfied 2026-08-10.** Evidence: `.work/docker-sandbox-substrate/probe-evidence-hardened-recipe.md`.
All three assertions failed inside a live boundary.

**Carried into Phase 2 — Phase 1 does NOT satisfy the Q21 probe obligation.** Target selection is
load-bearing, and the shipped recipe does not yet require a target drawn from what the run's installed
components may reach. Measured consequence: 201,961 bytes of origin data crossed a global
default-deny through a component-installed allow rule. Until that leg lands, a conforming transcript
can still certify a boundary that is open.

**What the live run changed.** It was not a formality — it found two recipe defects and one stale
environment claim that no amount of review would have caught:

- **The peer-identity design is empirically vindicated, not merely reasoned.** The measured boundary
  presented a certificate with the CORRECT hostname signed by a CA it trusted, so
  `ssl_verify_result=0` — certificate verification returned SUCCESS on a fully sealed boundary. Only
  the differing fingerprint distinguished interception from reached egress. This substrate is a live
  instance of the TLS-inspection case, not a hypothetical one.
- **A direct-TLS fingerprint tool cannot traverse an HTTP `CONNECT` proxy** and reports no peer at
  all, identically for a sealed and an open boundary. The recipe now requires a proxy-aware capture.
- **The probe shape now shows fail-on-HTTP-error explicitly.** The first attempt at the live run
  reproduced the original false negative exactly — a block page is a successful transfer.
- **Handoff correction, itself corrected during cleanup.** The global deny-all posture did NOT appear
  in `policy ls` while two kit-scoped policies were present, which is what made it read as absent — and
  the first version of this note wrongly concluded that the listing never displays the global policy.
  Once both sandboxes were removed, the listing showed `default-deny-all` plainly. The mechanism behind
  the earlier omission is unexplained and is NOT claimed here. What holds either way:
  **`policy check network <host>` is the authoritative confirmation route**, because it reports the
  effective decision rather than the listing's view of it.

**PR review outcome (#2150).** Two reviewers — one cross-vendor, one same-vendor — independently
converged on the SAME five findings, which is what marked them real rather than stylistic. All five
were confirmed and fixed; 474 checks pass, 0 pre-existing pinned reasons changed.

- **One was a stale-justification failure worth carrying forward as a lesson.** The plan recorded that
  the non-zero-exit invariant "stands unchanged — no relaxation", justified by the claim that
  certificate verification achieved the same discrimination while keeping the exit requirement.
  Certificate verification was then REPLACED by peer-identity comparison, which destroyed that
  justification, but the exit requirement survived unexamined — leaving a sealed boundary whose block
  page carries a successful HTTP status unprovable. A zero exit is now accepted only where the entry's
  outcome is `peer-substituted` and its fingerprints differ. **When a decision's premise is replaced,
  re-derive every rule that premise was carrying.**
- **The other four shared one shape: counting entries where coverage was meant.** Two egress entries
  counted as two targets (`example.com,example.com` passed); three canary strings counted as three
  shapes (`same,same,same` passed); fingerprints went unchecked on outcomes that assert no peer;
  `",,"` counted as three recorded exit codes. **Phase 3 inherits this directly** — a role list, a
  relational constraint, and a predicate set are all count-shaped surfaces, and the same defect is
  available in each unless the checks assert distinctness and coverage rather than length.
- **Pushed back on one half-suggestion rather than complying:** the checker has no trustworthy way to
  verify two hosts belong to different operators, since every signal it could read comes from the same
  transcript an executing agent authored. The recipe states the requirement; the checker enforces the
  verifiable part; the gap is recorded rather than implied.

Review: security

Criterion 3. Delivers the Q20 resolution above.

- [ ] **Pre-flight consumer check** (FIRST work item — this migrates the probe-transcript contract):
      `Grep` for `egress_denied`, `credentials_absent`, `outer_context_networked`, and
      `verifyProbeTranscript` across `plugins/`, `scripts/`, and `.github/`; document every parse
      path. Known consumers at plan time: `scripts/check-security-binding.mjs`,
      `scripts/check-security-binding.fixtures.test.mjs`, the fixtures manifest, and
      `skills/setup/SKILL.md`'s guardrail slice.
- [ ] **Hardcoded assertion COUNTS must move with the assertion set** — verified present at
      `templates/isolation-probe.md:6` ("the SAME two assertions"), `:13` ("Two checks"), `:103`
      ("both assertions"), and `schemas/guardrails-security-binding.schema.json:178` ("capture shape
      with both assertions"). Leaving any of them stale makes the contract self-contradicting.
- [ ] `templates/isolation-probe.md` — reword the egress assertion to the peer-comparison form and add
      its readiness, multi-target, and address-family legs; add the
      `workspace_host_write_contained` assertion with its outer-first, post-teardown probe shape and
      per-substrate wrapping note; extend the transcript capture shape with both new blocks.
- [ ] `reference/guardrails/isolation-ladder.md` — the `L2` level text names default-deny egress and
      credential protection; add host-write containment as the third property a boundary must
      demonstrate, and state the read-exposure limitation in the same breath. Classes only, no
      instance names.
- [ ] `scripts/check-security-binding.mjs` — extend `verifyProbeTranscript`: validate
      `egress_denied.transport_outcome` (closed token set, one entry per host, positionally paired)
      and the `workspace_host_write_contained` block. **Both new checks run LAST in the function** —
      `verifyProbeTranscript` returns the FIRST problem it finds, and all 58 `probe-evidence-*`
      fixture cases pin a `findings_substrings` naming their own specific rejection reason (verified:
      `records assertions.egress_denied.host "192.88.99.1"` and the like). A new check running
      earlier would return the new reason instead and rewrite every one of them.
- [ ] Transcripts referenced by PASSING fixtures gain both new blocks — exactly 6 JSON files:
      `ci-pool-a-l2.json`, `ci-pool-a-l2-as112-v6.json`, `ci-pool-a-l2-multi-host.json`,
      `ci-pool-a-l2-id-rsa.json`, `ci-pool-a-l3.json`, `ci-pool-a-l3-hosted.json`
      (`ci-pool-a-l1-2026-07-01.txt` is an `L1` reference and is not verified).
- [ ] New NEGATIVE transcripts + manifest cases: missing `workspace_host_write_contained`; a canary
      visible on the host post-teardown; `git_config_digest` changed; missing `transport_outcome`;
      count mismatch against `host`; a matching peer fingerprint with data read; a single-target
      egress probe; an unproven TLS client.
- [ ] `skills/setup/SKILL.md` — the guardrail slice's probe narration gains the third assertion.
- [ ] **Staged activation — this raises the `L2` bar for surfaces already bound.** Every deployed `L2`
      binding was probed under the two-assertion recipe, so its transcript has no third block; the new
      check makes those levels UNPROVEN, and the ladder's fail-closed rule then BLOCKS autonomous
      dispatch on that surface. `L3` inherits it. That is the correct security outcome and it is a
      breaking migration for every existing adopter, so it ships staged, never silently:
      (a) the release notes and `CHANGELOG` state the bar raise and what re-probing costs;
      (b) the checker's UNPROVEN finding text names the third assertion as the cause and points at the
      updated recipe, so an operator reads a remedy rather than a bare rejection;
      (c) the plugin `version` bump is MINOR at minimum, and the CHANGELOG entry is written as a
      migration note. In-repo fixtures are NOT the migration — they are only the test of it.
- [ ] **Merge gate — re-probe on a real substrate.** The reworded egress assertion has never been run;
      the existing evidence was captured under the OLD recipe. The stopped `probe-l3` sandbox is still
      on this machine, so re-probing is cheap. At least one real substrate must be re-probed under the
      hardened recipe before this phase merges, and the transcript committed as updated evidence.

**Sanity Check:**

- `node scripts/check-security-binding.fixtures.test.mjs` exits 0 with every pre-existing case's
  `findings_substrings` unchanged (diff the manifest: only ADDED keys, no MODIFIED `findings_substrings`
  on pre-existing cases).
- The template documents the assertion in both places that matter, asserted precisely rather than by
  token count: `grep -c "Workspace host-write containment probe shape" templates/isolation-probe.md`
  returns 1, and `grep -c "workspace_host_write_contained" templates/isolation-probe.md` returns ≥ 1
  (the transcript capture shape).

  *Correction, 2026-08-10, found at implementation.* The original `≥ 3` literal-token count was
  arbitrary and failed against a template that documents the assertion correctly in prose. Padding the
  document to satisfy the count would have been the wrong repair.
- `grep -rn "SAME two assertions\|Two checks\|both assertions\|two assertions" plugins/autonomy/skills/setup/`
  returns empty — every hardcoded assertion COUNT moved with the assertion set.

  *Correction, 2026-08-10, found at implementation.* ~~`must fail to CONNECT`~~ was wrongly included
  in this zero-match list. That phrase belongs to the CREDENTIAL assertion's metadata-endpoint clause,
  where connection-level failure is still the correct requirement; only the EGRESS assertion changed.
  Deleting it would have damaged sound contract text to satisfy a bad check.
- `grep -rn "sbx\|Docker Sandboxes\|Multipass\|Hyper-V" plugins/autonomy/` returns empty.
- A re-probe transcript exists under `.work/docker-sandbox-substrate/` recording the new
  `transport_outcome` and `workspace_host_write_contained` blocks from a live run.

#### Phase 2: Verification-topology contract leaf + matrix column [DONE]

**SHIPPED** as `f7d96afc`, then repaired twice under independent audit (`0c75e0a9`, `8172ab67`).

**Both repair rounds found the SAME defect shape the phase before it did — a count that does not
guarantee the coverage it exists for.** Round 1: `min_checkers` counted role TYPES, so a class
declaring `[A, A, B]` satisfied a floor of 3. Round 2, inside the repair itself: relations and
predicates bind only model-adjudicated slots, so three DETERMINISTIC slots met `C4`'s floor while
`cross_vendor_required` bound the empty set of model slots and was vacuously satisfied — a binding
valid with no model judge at all, against a matrix cell that mandates AI review. **Three occurrences
across two phases makes this the effort's signature failure, not an incident.** The generalization
worth carrying: whenever a rule counts things, ask what it would accept if every counted thing were
identical.

Other findings the audit closed: distinctness stated as "implied", which a validator cannot act on
because a slot NAME says nothing about what it resolves to; a budget ceiling written as invalidating,
which would have made this leaf the single enforcing exception to the matrix's own out-of-scope
statement on cost; three pointers citing support no file carried; and a deliberation clause resting
on an uncited measurement — replaced by the argument that is actually analytic, with the measurement
and its confidence grade moved to issue #2110.

#### Phase 2 (original brief)

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
      **The leaf contains no capability label at all** — not even as a rejected example. Criterion 4
      says "no capability label anywhere in it", and a rejected-vocabulary section would still put the
      words in the normative artifact. The leaf states only that capability labels are rejected as
      policy vocabulary, because they name a different thing at each vendor and do not survive a model
      release; the sourced per-label rationale lives in the PR body and issue #2110, which is where a
      future reader tempted to reintroduce one will find it.
      States the two fixed invariants: **independent aggregation, never deliberation**, and
      **unanimous checker agreement for anything auto-proceeding**.
- [ ] `reference/guardrails.md` — add the **Verification topology** column to the matrix, its
      one-line column definition, and a glance-layer routing row to the new leaf. Depth stays in the
      leaf; the hub gains no prose beyond the row.

**Sanity Check:**

- `grep -rniE "frontier|flagship|daily driver" plugins/autonomy/reference/` returns EMPTY — criterion
  4's "anywhere in it" is a zero-match assertion, not a scoped one.
- `plugins/autonomy/reference/guardrails.md` matrix header row contains `Verification topology`, and
  the glance-layer table contains a row pointing at `guardrails/verification-topology.md`.
- Every plugin-internal link in the new leaf resolves (`skill-reference-verify` hook passes).

#### Phase 3: Per-class verification floors on the security binding [DONE]

**SHIPPED** as `16a50974`. 522 checks / 148 fixtures, manifest diff purely additive (16 added, 0
removed, 0 pre-existing `findings_substrings` modified — verified semantically, not by eye).

**The floor table gained a fourth axis the brief did not name.** `min_model_checkers`
(`C1` 0 · `C2` 0 · `C3` 1 · `C4` 2 · `C5` 2) exists because a total count cannot express which KIND
of coverage is owed. Without it the `C4` all-deterministic binding above is valid.
`cross_vendor_required` is now never vacuously satisfiable, and vendor disjointness holds among the
model slots rather than only against the generator.

**One contradiction surfaced only by running it:** the pairwise-distinctness check demanded a
relational constraint between every checker pair, while the deterministic/model split rejects those
same constraints on deterministic slots — so a conforming binding was unrepresentable. Scoped to
model slots, since a cross-kind pair is distinct by construction. **A rule pair can be individually
sound and jointly unsatisfiable; only executing it shows that.**

#### Phase 3 (original brief)

Review: security

Criterion 5, binding half.

- [ ] **Pre-flight consumer check** (FIRST work item): `Grep` for `verification_blocking`,
      `merge_policy`, and `schema_version` parse sites across the plugin and repo scripts.
- [ ] `schemas/guardrails-security-binding.schema.json` — add `verification_topology` as an
      OPTIONAL top-level key. **Criterion 4 says the policy is expressed as roles + relations +
      MACHINE-CHECKABLE predicates; a predicate that never reaches the schema is not machine-checkable,
      so all three axes are modeled here, not only the count.** Per class: `min_checkers` (integer ≥ 1),
      `cross_vendor_required` (boolean), and a role list whose entries carry the relational constraints
      (`distinct_model_from`, `distinct_vendor_from`) and the predicates (`min_context_tokens`,
      `requires_modality`, `requires_feature`). Optional-with-contract-defaults follows the
      `escalation_severity` precedent, so `schema_version` stays `"1.0"` and all 113 existing fixtures
      continue to validate. Absent binding is NOT a hole: the leaf's shipped floors apply, exactly as
      `escalation_severity` falls back to contract defaults.
- [ ] `scripts/check-security-binding.mjs` — floors are FLOORS: tightening legal, weakening below the
      shipped default invalid, no `override_justification` escape (the same rule
      `verification_blocking` already carries). A relational constraint naming a role absent from its
      own class's role list is invalid — that check is what makes the predicate machine-checkable
      rather than decorative.
- [ ] New fixtures: a valid tightened binding; a weakened `min_checkers`; a `cross_vendor_required`
      dropped below its floor; a non-class key; a `distinct_vendor_from` pointing at an undeclared
      role; an unknown predicate token.

**Sanity Check:**

- `grep -c '"schema_version": { "const": "1.0" }' plugins/autonomy/skills/setup/schemas/guardrails-security-binding.schema.json`
  returns 1 (the version did NOT move).
- `node scripts/check-security-binding.fixtures.test.mjs` exits 0; the 22 pre-existing exit-0 cases
  still exit 0 unmodified.
- Every axis named in the leaf appears as a schema key: for each of `min_checkers`,
  `cross_vendor_required`, `distinct_model_from`, `distinct_vendor_from`, `min_context_tokens`,
  `requires_modality`, `requires_feature`, `grep -c` in the schema returns ≥ 1.
- The undeclared-role fixture exits 1 with its pinned finding — proof the relational constraint is
  enforced, not merely declared.

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

**Honest limit.** Criterion 6 says the lane "cannot block". With no runner built, there is no runtime
in which to demonstrate that, and building one is barred by the Brief's own trigger-gate constraint.
So the criterion is met by **structural impossibility rather than a runtime test**: the lane is given
no blocking knob in `userConfig` and no `VerificationKnob` cell in the schema, so there is nothing an
org could flip. The runtime ordering assertion — deterministic pass plus visual fail still advances —
is recorded as a deferred item bound to the runner's build trigger, not claimed here.

**Sanity Check:**

- The visual lane's section in `reference/guardrails/verification-topology.md` contains no
  `blocking` token: `grep -c blocking` over that section returns 0.
- `grep -c "visual" plugins/autonomy/skills/setup/schemas/guardrails-security-binding.schema.json`
  returns 0 — the lane has no binding-side knob at all, which is what makes it unpromotable.
- `node -e "JSON.parse(require('fs').readFileSync('plugins/autonomy/.claude-plugin/plugin.json'))"`
  exits 0 and every new `userConfig` entry has a `default`.
- The commit message cites the fetched docs URL.

#### Phase 5: Merge gating and disagreement routing [TODO]

Review: security

Criterion 7.

**Routing question — RESOLVED, not deferred.** Verified this session: `verification-divergence` is
already a REQUIRED key in `escalation_routes`, and `guardrails.md` defines it as "a verification
outcome diverges from the expected or claimed result" — which is exactly implementer/checker
disagreement. Phase 5 binds to it and invents no token. The new machinery is the **unanimity
predicate**, not the event class.

- [ ] `reference/guardrails.md` — merge-policy column keeps human merge; record that **every automatic
      transition**, not merely a merge, requires unanimous checker agreement. Scoping it to merge alone
      would leave an auto-advancing pipeline stage ungoverned, which is the hole criterion 7 exists to
      close.
- [ ] `reference/guardrails/work-classes.md` — the unanimity requirement joins the promotion
      discipline: a promoted `C2`/`C3` auto-merge cell still does not auto-proceed on checker dissent.
      Promotion does not survive dissent; it is a ceiling, and dissent lowers the effective state the
      same way contrary evidence already does.
- [ ] `scripts/check-security-binding.mjs` + fixtures — a binding whose `merge_policy` is `auto` for a
      class whose `verification_topology` floor cannot express unanimity is invalid.

**Honest limit.** Criterion 7's "unanimous agreement to auto-proceed" is a RUNTIME aggregation rule,
and the runner that would aggregate is design-only and trigger-gated — `runner.md` states "no build
begins until a T4 build trigger fires". This phase therefore delivers what is checkable without a
runtime: the contract obligation, the promotion-discipline consequence, and a binding-validity check
that a class cannot be configured to auto-proceed without a floor capable of expressing unanimity.
The per-run verdict-aggregation gate (unanimous pass, single dissent, checker timeout, duplicate
checker identity) is specified as a runner-seam obligation and lands with the runner build. The plan
does not claim enforcement it cannot demonstrate.

**Sanity Check:**

- `grep -n "unanimous" plugins/autonomy/reference/guardrails.md plugins/autonomy/reference/guardrails/work-classes.md`
  returns a match in both — a documentation assertion, and labeled as such.
- The BEHAVIOR assertion: a new fixture binding `merge_policy.C3 = "auto"` with a
  `verification_topology` floor that cannot express unanimity exits 1 with its pinned finding, and the
  otherwise-identical binding with a conforming floor exits 0.
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
| Certificate verification alone as the egress discriminator (this plan's own first draft) | An org that installs a TLS-inspection CA inside the boundary makes the interceptor verify cleanly, so the check grades an intercepted boundary as egress-capable. Replaced by a peer-fingerprint comparison against the outer context, which assumes no trusted CA |
| An origin-signed nonce challenge verified against an embedded public key | Strictly stronger, but no well-known public endpoint will sign a caller-supplied nonce, so it cannot be substrate-agnostic or vendor-neutral — it would require shipping and operating an endpoint, which this repository has no business doing |
| A new escalation mechanism for checker disagreement | `verification-divergence` already exists, is already required in `escalation_routes`, and its definition already means this — verified this session, so Phase 5 binds rather than deferring |
| Prohibiting automatic merge outright to satisfy criterion 7 | Overshoots the criterion, which permits auto-proceeding on unanimity, and would revoke the shipped `C2`/`C3` promotion path the guardrail matrix already grants. Unanimity is scoped to every automatic transition instead |
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
- **Phase 5:** the documentation greps are labeled as documentation assertions; the behavior assertion
  is the paired fixture (auto-merge with a unanimity-incapable floor exits 1; the conforming twin
  exits 0).
- **Covered only by a live re-probe, not by the fixture harness:** whether the reworded egress and
  workspace assertions actually discriminate on a real substrate. Fixtures test the CHECKER, never the
  RECIPE. This is why the live re-probe is a Phase 1 merge gate rather than a suggestion.
- **Not covered at all, and stated rather than hidden:** runtime behavior for criteria 6 and 7. No
  runner exists to exercise them, and building one is barred by the Brief's trigger-gate constraint.

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Phase 1 blocks autonomous dispatch for every existing adopter.** Their `L2` transcripts predate the third assertion, so the levels go UNPROVEN and the ladder's fail-closed rule blocks the surface. `L3` inherits it | **Certain** | **High** | This is the intended security outcome of a bar raise, but it is breaking. Staged activation is a Phase 1 work item: remedy-bearing finding text, a migration CHANGELOG note, and a MINOR-at-minimum version bump. In-repo fixtures are the test of the migration, never the migration itself |
| The new transcript checks run before existing checks and rewrite 58 pinned `findings_substrings` | High | Med | Last-position ordering is a stated implementation constraint; the "no pre-existing substring changed" assertion catches it mechanically |
| A TLS-inspection CA trusted inside the boundary makes an interceptor's certificate verify cleanly | Med | High | Why the assertion is a peer-fingerprint COMPARISON against the outer context rather than plain certificate verification — it needs no trusted-CA assumption. First-draft cert-verification-only was rejected for exactly this |
| A boundary with no working TLS client "passes" trivially — a missing tool looks like a denied network | Med | High | The client-readiness leg: the same client must succeed against an in-boundary endpoint first, or the level is UNPROVEN |
| One denied target certifies default-deny while policy quietly allows others | Med | High | Two targets minimum, one a randomized name no allowlist anticipated. Note the adjacent kit-widening question is Q21 and stays USER-RESERVED — this leg strengthens the probe without deciding it |
| **The assertion does not cover READ exposure, and clone mode leaves reads fully open** | Certain | Med | Named limitation carried in the assertion's own name (`workspace_host_write_contained`) and stated in the leaf. Widening to reads is a deferred item with a trigger, not an implied guarantee |
| A caching or async mount propagates the inner write after the post-check | Med | High | Post-check runs after boundary teardown, with both sides canonicalized |
| Shipped floor VALUES are unevidenced | High | Med | OPEN DECISION 1 below — BLOCKS Phase 3, not the plan's approval |
| The hardened recipe is never re-run against a real substrate | Med | High | Promoted from advisory to a Phase 1 MERGE GATE — the stopped `probe-l3` sandbox is still on this machine |
| Criteria 6 and 7 are runtime claims with no runtime to test them in | Certain | Med | Both are met by structural impossibility plus contract obligation, and each phase states the limit explicitly. The runtime assertions are recorded as runner-seam obligations bound to the build trigger — not claimed as delivered |
| Pipeline evidence is pre-consensus and several findings are single-study | High | Med | The leaf records each choice's evidence basis, so a later contrary result demotes that choice explicitly rather than silently contradicting a rule with no stated warrant |
| Scope creep from Q21 into Phase 1 | Med | Med | Q21 is USER-RESERVED; no phase depends on it. If a phase starts to, that is drift and stops |

### OPEN DECISIONS — not resolved by this plan

1. **Shipped per-class floor values** (`min_checkers`, `cross_vendor_required`). **BLOCKS Phase 3**,
   not this plan's approval. The interview fixed the SHAPE, never the numbers, and no research lane
   sets them — so choosing them here would be a sizing guess dressed as evidence. RECOMMENDED starting
   floors: `C1` 1/no · `C2` 1/no · `C3` 2/no · `C4` 3/yes · `C5` 3/yes. They are FLOORS, so an org may
   only tighten, and the cross-vendor requirement lands on exactly the two classes whose cost the
   evidence justifies.
2. **PR granularity.** RECOMMENDED: Phase 1 ships as its own PR — it is self-contained,
   security-bearing, independently revertable, and it carries a breaking migration that deserves its
   own release note. Phases 2–5 ship as a second PR carrying the topology change coherently.
   Alternative: one PR per phase, five review round-trips.

### Reserved decisions — RESOLVED 2026-08-11

All three were USER-RESERVED through planning and Phase 1. Research reframed two of them; the third
was settled empirically rather than argued. Evidence:
`.work/docker-sandbox-substrate/RESEARCH-reserved-questions.md`.

#### Q21 — the ladder gains a class-level property, not a vendor-shaped rule

**Decision: an `L2`+ binding must assert that nothing the run can install is able to WIDEN the
boundary — only narrow it.**

The vendor already solves this under organization governance, where the documented precedence is
`kit allow ✗ / kit deny ✓` — *"Precedence is decided by a rule's decision rather than its source."*
It does NOT solve it in local-policy-only mode, which the vendor's table leaves unstated and which
this session measured: a component installed at sandbox-create time widened egress past a global
default-deny, and **201,961 bytes of origin data flowed**, with the origin's own CA on the wire.

Naming the vendor's component type here would violate the ladder's classes-never-vendors rule, and
would not generalize. The property does: it covers browser-extension permissions, admission
controllers, and any additive policy engine.

Work items (land with the Phases 2–5 PR, since Phase 1 already edits this file):

- [ ] `reference/guardrails/isolation-ladder.md` — state the property on `L2`. An additive policy
      engine whose components can only narrow satisfies it; one where an installed component can widen
      does not, and that surface fails closed until governance is configured so it cannot.
- [ ] `templates/isolation-probe.md` — **the probe obligation this creates.** Target selection is
      load-bearing: a probe sampling only hosts the installed components do NOT allow will certify a
      boundary that is in fact open. The recipe must require probing in the configuration the run will
      actually use, with at least one target drawn from what the installed components are permitted to
      reach.
- [ ] Fixture: a transcript whose probed targets exclude every component-allowed host is not a
      conforming capture.

#### Q22 — the three software-factory gaps get triggers in the T4 idiom

**Decision: drafted below in the runner charter's trigger idiom — a named, judgement-free condition,
explicitly not assumed to have fired.** Wording is for review.

- **Fleet-level economics as tracked output.** *Trigger:* the return-accounting and telemetry contracts
  are both bound and emitting for more than one repository under one org binding, AND a question is
  asked of that data which per-run records cannot answer (cost or yield compared ACROSS repositories).
  Until then the existing per-run contracts cover the need and a fleet aggregate would have no second
  repository to aggregate.
- **Portfolio-scale multi-repo fan-out as a unit of work.** *Trigger:* a single work item requires
  coordinated change across two or more repositories with a shared acceptance criterion, and the
  per-run seams cannot express it without a human sequencing the runs. Until then every seam is
  per-run by construction and fan-out has no unit to carry.
- **Self-service golden paths for humans and agents.** *Trigger:* a second adopter (any consumer
  outside the authoring org) completes guided setup, OR the setup interview's unanswered-value rate
  makes the interview itself the bottleneck. Until then a golden path would be generalized from a
  single deployment, which is the sample size this repository already rejects elsewhere.

Each is recorded as DEFERRED WITH A TRIGGER, never as rejected — the ladder's own "Rejected axis"
section is reserved for what was deliberately not chosen, which these are not.

**Wording RATIFIED 2026-08-11 as drafted.** The three triggers stand verbatim; the review the user
reserved is closed. Nothing downstream depends on the phrasing, so a later revision costs a wording
commit and no rework.

#### Q23 — event-triggered re-verification, with a staleness bound as backstop

**Decision: re-verify on events that could change the probed property; cap evidence age separately.
No cadence keyed to release frequency.**

The corpus already rejected the framing the question assumed. Release cadence is *evidentially inert*:
CISA warns against reading fix counts as a negative signal; Ozment & Schechter measure median
foundational vulnerability lifetime at **≥2.6 years** with ~67.6% found after 7.5; Rescorla cannot
exclude a constant discovery rate. Three weeks is not a sample, so a release-frequency cadence would
be ritual rather than control.

- **Re-verification events:** a substrate version change touching the probed boundary; a policy-engine
  or governance-mode change; a change to the installed component set (which Q21 just proved can widen
  the boundary without any version change at all).
- **Staleness bound:** evidence older than the repository's existing **">2-month"** idiom is stale
  regardless of events. Reusing that number rather than inventing one — it is already the corpus's
  own gate.
- **What re-verification covers:** the specifics that rot — flags, defaults, guarantees. The
  architecture and posture findings are durable and are not re-derived each time.

### Deferred, with triggers — recorded so they are not silently implied

- **Workspace READ-exposure assertion.** Trigger: any adopter binds a substrate whose workspace mount
  is readable and whose threat model includes workspace exfiltration. Q6 scoped this round to
  write-back; the assertion's name says so.
- **Runtime verdict-aggregation gate** (unanimous pass, single dissent, checker timeout, duplicate
  checker identity). Trigger: the runner's T4 build trigger fires. Specified as a runner-seam
  obligation in Phase 5; not deliverable before a runtime exists.
- **Runtime advisory-ordering assertion** (deterministic pass plus visual fail still advances). Same
  trigger.

These are distinct from Q21/Q22/Q23, which are USER-RESERVED and belong to the human, not to a
trigger.

### Blast radius

**HIGH.** The change touches an agent-unwritable security surface, a fail-closed checker with 113
gated fixture cases, the isolation ladder's definition of `L2`, and a plugin manifest consumers
install. Triggers matched: security-sensitive surface; contract migration with downstream consumers;
fail-closed policy semantics. Phase 1 additionally halts autonomous dispatch for every existing
adopter until they re-probe, which is a breaking migration on a security floor.

### Stress-test summary

Two independent passes were attempted; one channel worked.

- **Fresh-context sub-agent review (Step 3): FAILED TO DELIVER.** Three separate spawns each returned
  an idle notification with no report. The subagent return channel is broken in this session. Recorded
  rather than papered over, because Step 3 is mandatory and a silent skip would be the failure mode
  the step exists to prevent.
- **Cross-vendor review (Codex): DELIVERED.** This is the route the skill names as PREFERRED over the
  same-vendor sub-agent, so the fallback failing did not cost independence. Its findings drove the
  revisions above: the TLS-inspection defeat of certificate verification, the client-readiness and
  multi-target gaps, the async-propagation and canary-shape gaps in the workspace assertion, the
  unaccounted `L2` migration, the documentation-only predicates, the capability labels leaking into
  the normative leaf, and Phase 5 testing expressibility rather than behavior.
- **Findings verified before applying, not taken on trust.** Confirmed against the files: the
  hardcoded assertion counts at `isolation-probe.md:6,13,103` and `schema:178`; criterion 4's literal
  "anywhere in it"; `runner.md`'s "no build begins" (which is what makes criteria 6–7 runtime-untestable).
  Confirmed harmless: `human-gated-only-no-l2.json` binds only `L1` and has an empty
  `findings_substrings`, so the bar raise does not flip it.
- **Findings REJECTED with reasons:** prohibiting automatic merge outright (overshoots criterion 7 and
  revokes a shipped promotion path) and the origin-signed-nonce challenge (cannot be vendor-neutral
  without operating an endpoint). Both are recorded in Alternatives Considered.
- **What the stress-test does NOT establish.** It was an independent READING of the plan against the
  files. Nothing was executed: no fixture harness run, no substrate re-probed, no checker exercised.
  The review inherits the Test Strategy's own limit — it can find a wrong plan, not prove a right one.
  The live re-probe merge gate exists because no amount of review substitutes for running the recipe.

### Execution shape

Phase 1 is file-disjoint from Phase 2 and depends on nothing; every other phase is gated.

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | probe template, isolation-ladder, checker, manifest, fixtures, transcripts, SKILL, CHANGELOG | 3, 5 (checker, manifest, fixtures) · 4 (SKILL, CHANGELOG) |
| 2 | guardrails.md, verification-topology.md (new) | 3, 4 (leaf) · 5 (guardrails.md) |
| 3 | schema, checker, manifest, fixtures, leaf | 1, 5 · 2, 4 |
| 4 | plugin.json, SKILL, leaf, CHANGELOG | 1 · 2, 3 |
| 5 | guardrails.md, work-classes.md, checker, fixtures | 1, 3 · 2 |

Dependency graph: Phase 2 defines the vocabulary Phases 3–5 cite, so 2 gates all three. Phase 3's
schema is what Phase 5's binding-validity check reads, so 3 gates 5. **Phase 1 is independent of every
other phase.**

**Recommended shape: sequential, 2 → 3 → 4 → 5, with Phase 1 free to run concurrently.** Phase 1 and
Phase 2 are genuinely file-disjoint, and under the recommended PR granularity they land in separate
PRs anyway — so concurrency there is free rather than orchestrated. Within the 2–5 chain the file
overlap on the checker and the topology leaf is heavy enough that parallelism would cost more in
conflict handling than it saves.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | Security-bearing contract change with a breaking migration; judgment-heavy throughout |
| 2 | main-session | Normative contract prose; the vocabulary every later phase cites |
| 3 | main-session | Schema plus checker semantics on the agent-unwritable surface |
| 4 | main-session | Gated on a live docs fetch and a manifest contract change |
| 5 | main-session | Promotion-discipline semantics; the highest-consequence cell in the matrix |
| 6 | main-session | Close-out, prune, PR body, issue comment |

No phase routes to a sub-agent worker. Two reasons, both real: every phase is judgment-heavy contract
work rather than mechanical volume, and the sub-agent return channel demonstrably failed three times
in this session. If a later session finds the channel healthy, Phase 1's fixture authoring is the one
slice that would delegate cleanly.

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| `[EXEC-SHAPE]` Peer-fingerprint comparison, not certificate verification, as the egress discriminator | The Q20 egress resolution and the `transport_outcome` token set | Certificate verification is defeated by a TLS-inspection CA trusted inside the boundary; a comparison against the outer context's fingerprint assumes no trusted CA at all |
| `[EXEC-SHAPE]` The workspace assertion is named `workspace_host_write_contained` | The assertion name, the leaf text, and the deferred read-exposure item | Q6 scoped this round to write-back, and clone mode leaves reads fully open — the short name would have implied coverage the assertion does not provide |
| `[EXEC-SHAPE]` Post-check runs after boundary teardown, with randomized canaries across three path shapes | Phase 1's probe shape | A caching or asynchronously-flushed mount can propagate after an immediate check; a single literal path misses case-folding and hidden-file handling |
| `[EXEC-SHAPE]` Optional-additive schema keys; `schema_version` stays `"1.0"` | Phase 3's schema change and the 113-fixture regression floor | `escalation_severity` and the `runner-*` keys are the house precedent, described in the schema as preserving existing bindings. Verified: `const "1.0"` |
| `[EXEC-SHAPE]` New transcript checks run LAST in `verifyProbeTranscript` | Phase 1's implementation constraint and its Sanity Check | The function returns the first problem found, and all 58 `probe-evidence-*` cases pin their own rejection reason |
| `[EXEC-SHAPE]` The normative leaf contains no capability label at all, not even a rejected one | Phase 2's leaf content and its zero-match Sanity Check | Criterion 4's literal text is "no capability label ... anywhere in it"; the sourced rationale moves to the PR body and #2110 |
| `[FALLBACK — confirm or override]` Staged activation rather than an immediate hard cutover for the `L2` bar raise | A new Phase 1 work item and the top Risks row | The Brief did not anticipate that raising `L2` blocks dispatch for existing adopters. Fail-closed is correct; shipping it without a migration note is not |
| `[FALLBACK — confirm or override]` Criteria 6 and 7 are met by structural impossibility plus contract obligation, with the runtime assertions deferred to the runner build | The honest-limit notes in Phases 4 and 5, and two deferred items | `runner.md`: "no build begins until a T4 build trigger fires", and the Brief locks that constraint. The alternative would be claiming enforcement that cannot be demonstrated |
| `[EXEC-SHAPE]` Live re-probe promoted from advisory to a Phase 1 merge gate | Phase 1's merge gate and the Test Strategy | Fixtures test the checker, never the recipe; the reworded assertions have never been run against a real boundary |
| `[EXEC-SHAPE]` The Tier A design gate is satisfied by the interview register rather than re-running `/planning:design` | `design/design-resolution.md` exists instead of a design pack | Rounds 3–5 resolved every design thread and the register gated clean; each thread is mapped to its resolving question in that file |

### Open questions

- OPEN DECISION 1 (floor values) resolved 2026-08-11; Phase 3 shipped against it.
- Q21, Q22, Q23 were USER-RESERVED and are RESOLVED 2026-08-11 — see the resolutions below. Earlier
  USER-RESERVED markers in this document predate that and are stale where they conflict.

### Handoff to implementation

#### User-approval gates

- Both `[FALLBACK]` rows above, before the phase that implements them.
- OPEN DECISION 1, before Phase 3.
- Phase 1's merge gate: the live re-probe transcript is reviewed before the phase merges, because it
  is the only evidence the reworded recipe works.

#### Execution shape

Sequential 2 → 3 → 4 → 5, Phase 1 concurrent and independent, all main-session. No scope-fencing
tables — no phase is delegated.

#### Mechanical work

Commit boundaries follow phases. Stage explicit paths, never `git add -A`. The contract slice
`docs/topics/docker-sandbox-substrate/` is pruned in the final commit before merge, and the PR body
carries the closing keyword plus a non-empty `## Related` section or CI fails on the linkage check.

