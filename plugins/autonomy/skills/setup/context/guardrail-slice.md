# Guardrail slice

One slice of the `apply` action in [`../SKILL.md`](../SKILL.md), selected by argument and run only
when `apply` reaches it. The hub's
[guardrail binding resolution](../SKILL.md#guardrail-binding-resolution) section owns how bound
policy resolves; this slice is the action that produces the binding it resolves.

Wires the enforced state of the [guardrail contract](${CLAUDE_PLUGIN_ROOT}/reference/guardrails.md):
detect → bind → live-validate → fail-closed, always detect-diff-reconciling against the org's
EXISTING guardrail surfaces. The [resolution section above](../SKILL.md#guardrail-binding-resolution) owns
how bound policy resolves across the two governance surfaces; this slice is the action that
produces the security binding it resolves. Everything lands as reviewable changes; paid scanner
SKUs are advisory + explicit opt-in with cost surfaced.

**This slice PREPARES, never writes the security surface directly.** The security binding lives
in the settings-as-code home, outside the blast radius of the agents it governs, a surface the
running agent cannot write (that is the whole point of the split). So the slice produces the
binding document and its locator-registry entry as REVIEWABLE CHANGES a human lands on the
governance surface (a proposed change on the settings-as-code home, a registry entry on the
org-policy home). It never mutates the agent-unwritable surface in place. Nothing autonomous
depends on the binding until that human-landed change exists.

1. **Detect substrates per level per machine surface**. For each execution surface the
   trigger/dispatch slice recorded (the same surface ids the security binding's
   `isolation_bindings` key on), inspect what isolation substrates are available at each ladder
   level per the [isolation-ladder leaf](${CLAUDE_PLUGIN_ROOT}/reference/guardrails/isolation-ladder.md):
   an `L2` whole-process OS-sandbox wrap or default-deny-egress container, an `L3` kernel-separated
   VM/microVM or hosted ephemeral executor. Detection is PER SURFACE, a substrate present on one
   surface says nothing about another, and the flat "some surface has L2" answer never satisfies a
   different dispatch surface.
2. **Detect-diff-reconcile against existing guardrail surfaces**, never greenfield-assume, never
   silently overwrite. Before proposing any binding value, read the org's EXISTING guardrail
   surfaces. Sandbox/runner configurations, branch protections, review workflows and scanner
   configuration, and DIFF the detected state against them. Where an existing surface already
   encodes a policy (a branch protection rule, a configured scanner, an isolation setting), the
   slice reconciles: it surfaces the diff and proposes the binding that matches or tightens the
   existing surface, and it never overwrites an existing surface as a side effect of binding. A
   pre-existing surface is authoritative input to reconcile against, not a blank field to fill.
3. **Live-validate BEFORE recording**, the empirical probe per substrate class (recipe in
   [`templates/isolation-probe.md`](../templates/isolation-probe.md)). A candidate `L2`/`L3`
   substrate is validated by running, INSIDE the boundary, three probes that MUST all fail:
   - a **denied-egress smoke test**, a network fetch MUST fail against two well-known external
     hosts under different operators AND against every destination the level binding ratifies as
     component-reachable (a boundary that lets egress through is not an `L2` boundary, and a probe
     that samples only what the base policy denies never looks where an installed component may
     already have widened it);
   - a **host-credential-path read attempt**, a read of a host credential path MUST be absent or
     denied (a boundary that leaks host secrets is not an `L2` boundary);
   - a **workspace host-write containment check**. Randomized canaries written inside MUST all be
     absent on the host after teardown (a boundary the host later executes writes from is not an
     `L2` boundary).

   The checker resolves no DNS and reads no remote host, so it validates the probe's targets against
   operator-configured seams. The egress target checks against `--egress-hosts <host,...>` (a
   configured trusted external target; without it the checker falls back to its
   local/private/encoded/special-use deny lists). Each host credential path checks against
   `--credential-roots <path,...>` DENY-BY-DEFAULT: a filesystem credential entry proves absence only
   when its recorded host-side expansion resolves under a configured trusted root, and with no roots
   configured every filesystem credential entry is untrusted and the level fails closed. A
   cloud-metadata-endpoint route and a well-known credential env token stay bounded closed sets that
   need no allowlist. The allowlist SHAPE (that these seams exist, and their schema) is a
   repo-committed convention; the host-secret-sensitive root VALUES, which reveal where an org's
   credentials live, bind per the deployment's secret-binding classification (a machine/userConfig
   binding), never inlined into the committed binding document.

   The binding for that level on that surface lands only when the probe transcript proves ALL
   THREE failures: denied egress, absent host credentials, and contained workspace host-writes;
   the transcript's reference is recorded in the level binding's `probe_evidence`
   field (schema-required, a binding without probe evidence is invalid per
   [`scripts/check-security-binding.mjs`](../scripts/check-security-binding.mjs)). A binding never
   lands ahead of the probe that proves its boundary.
4. **Bind level → substrate per surface**. Record each validated substrate under its surface in
   `isolation_bindings` (surface id → level token → substrate instance + the human-ratified
   `substrate_class` and `component_reachable_hosts` + `probe_evidence` + the non-forgeable
   `runtime_markers` the dispatch seam attests against), plus the merge policy,
   verification-blocking knobs, each class's `verification_topology`, escalation routes, and
   admission rules and caps. All on the
   prepared security-binding change, validated by
   [`scripts/check-security-binding.mjs`](../scripts/check-security-binding.mjs) against
   [`schemas/guardrails-security-binding.schema.json`](../schemas/guardrails-security-binding.schema.json)
   before it is proposed.
   The lens pool and the advisory visual narration lane are NOT binding fields. They resolve from
   plugin `userConfig` per the [third home above](../SKILL.md#guardrail-binding-resolution), and proposing
   either here is invalid.
5. **Security-review wiring folds in here (no separate capability)**, the security-review policy
   is one part of this single guardrail slice, never a near-duplicate setup capability. Wire the
   [security-review leaf's](${CLAUDE_PLUGIN_ROOT}/reference/guardrails/security-review.md) two
   layers (deterministic scanners + AI security review) into the binding's `verification_blocking`
   knobs, detect-diff-reconciling against the org's existing scanners, review workflows, and branch
   protections. Free-path scanner classes satisfy every blocking obligation on the DEFAULT path:
   zero paid dependencies. Entitlement-gated paid code-scanning SKUs stay advisory + explicit
   opt-in with cost surfaced at opt-in time; an entitlement gap routes the tool to the advisory
   path, never silently passing a blocking layer.
6. **Fail-closed verify**, when NO substrate on a surface reaches the `L2` floor, autonomous
   dispatch is BLOCKED for that surface and the slice names the compliant paths (provision an
   `L2`-capable substrate on the surface, or route the surface's work to a surface that has one,
   or keep the surface human-gated). Silent degrade to a lower level is never conforming. Under
   `dispatch_posture: human-gated-only` a surface with no `L2` binding is the org's DECLARED
   posture, not a defect, the verify reports blocked autonomous dispatch as declared, and the
   binding still validates.
