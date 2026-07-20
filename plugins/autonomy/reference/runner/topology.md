# Runner topology

The ownership seam map for the runner: which home owns which part of it, which backend the
launch set requires, and which decisions stay reserved for the human who fires the build
trigger. The map is fixed now, at design time; the homes it assigns are populated only when a
[build trigger](../runner.md#build-triggers) earns the build. This leaf defines only the
ownership seams — every level, floor, and matrix cell it references is cited from its owning
contract, never restated here.

## Ownership seams

Four homes own the runner between them; the split is a pre-committed seam, not a runtime choice.

- **Capability-distribution home — the design pack.** This pack lives here, alongside the other
  autonomy contracts. It owns the runner's vocabulary and obligations, never an implementation.
- **Runner-execution home — the implementation.** When a build trigger fires, this home is born
  owning the runner implementation and its build/release toolchain. It consumes the contract
  docs by citation and never duplicates them; until the trigger fires it does not exist.
- **Settings-as-code home — the security-sensitive bindings.** The runner's governance —
  level→substrate isolation bindings, merge policy, escalation routes, and admission rules —
  lives here. The runner READS its governance and never writes it: the agent-writable-binding
  bypass channel the rest of the contract fail-closes against generalizes to the runner itself,
  so no runner-editable surface may supply a binding the runner is governed by.
- **Deployment-owned — non-security operational config.** Executor hosting configuration that is
  not security-sensitive is the adopting deployment's, per the hosting stance.

## Launch backend set

The sandbox-provider seam is the normative requirement; the backend set below is what satisfies
it for the work the trigger admits. Backend classes are cited from the
[isolation ladder](../guardrails/isolation-ladder.md), never redefined.

- **One free self-run `L2` backend at launch.** A container-class substrate with a default-deny
  egress firewall satisfies the `L2` unattended floor at no standing cost; it is the only
  backend the launch set requires.
- **`L3` deferred, fail-closed until bound.** An `L3` backend is deferred with its trigger — the
  first `C5`-class work admitted to the autonomous drain. Until an `L3` binding exists, `C5`
  dispatch is BLOCKED, never dropped to a lower floor: the `L3` floor for `C5` work is the one
  the [work-classes `C5` cell](../guardrails/work-classes.md) fixes and this gate cites, not a
  value asserted here.
- **Paid and cloud backends — advisory, explicit opt-in.** No paid or cloud backend is a
  default; each is advisory with its cost surfaced first and reached only by explicit opt-in.
  Any cloud backend IS a vendor-hosted executor: selecting one forces the security binding's
  `executor_class: vendor-hosted`, which caps every merge row at human-gated — the same cap
  [the lifecycle leaf](lifecycle.md#disposition) restates on the disposition path. A cloud
  backend buys isolation, never an auto-merge it cannot own.

## Birth-time decisions — USER-RESERVED

Some decisions resolve only when the build trigger fires, and their arbiter is USER-RESERVED —
the trigger firing is a user-ratified event, never a choice implementation makes on its own:

- repo count, name, and implementation language, via the naming pass and the re-verified spine
  choice;
- the spine re-verification outcome — adopt the qualifying spine library, or fall back to
  reimplement-the-pattern;
- the exact managed-agent event-name bindings, bound at build from live surface docs.

## Absent settings-as-code home

An adopting org without a settings-as-code home does not lose the governance guarantee. Binding
resolution layers over whatever governance surfaces are available, and an absent security
binding fail-closes — the runner blocks rather than running ungoverned. Guided setup names the
compliant path to a home for the bindings; it never degrades to a repo-local (agent-writable)
one.
