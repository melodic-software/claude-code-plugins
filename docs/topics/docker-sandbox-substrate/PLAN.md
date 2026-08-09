# docker-sandbox-substrate

## Brief

### TLDR

Docker Sandboxes (`sbx`) was evaluated as an isolation substrate and as a possible route to an
agent-agnostic autonomous pipeline. It is a **substrate instance for a seam this repository already
specifies** — not a plugin, not a new repository, and not a framework. Integrating it costs **zero
files here**, because the guided-setup path already ships and the ladder forbids naming a product
instance in this repository at all. It was probed live on Windows 11 Pro under a hardened invocation
and **both isolation assertions passed**.

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

<!-- Filled by /planning:plan. -->
