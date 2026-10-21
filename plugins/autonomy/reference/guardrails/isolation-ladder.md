# Isolation ladder

Normative leaf of the [guardrail contract](../guardrails.md): the tool-agnostic isolation
ladder the matrix's min-isolation column keys on. Levels are contract vocabulary. Substrate
instances are org-supplied through the security binding per the guided-setup pattern. This
document names substrate classes as marked examples only, never an instance list.

## Levels

- **`L0`: worktree + VCS permissions only.** No OS boundary: the working tree and
  version-control permissions are the only containment. Attended interactive use only.
- **`L1`: per-command OS sandbox.** The sandbox wraps shell-command execution only; file
  tools, hooks, and protocol-connected tool surfaces still execute on the host. An attended
  ergonomics tier, not an autonomy tier. Which level a harness's own sandbox reaches is read live:
  see the guardrail slice's
  [sandbox rating record](../../skills/setup/context/guardrail-slice.md#harness-records-for-the-vendor-neutral-leaves)
  (as of 2026-10-11; recheck when that record's trigger fires, or the linked heading is renamed or
  removed).
- **`L2`: whole-process OS-enforced boundary with default-deny egress, credential
  protection, contained workspace host-writes, and policy nothing the run can install may
  widen.** The minimum for any unattended run, except on the
  [CI-lane surface](#ci-lanes-on-provider-hosted-runners).
  Free-path substrate classes (marked examples, not an instance list): a whole-process
  OS-sandbox wrap; a container with a default-deny egress firewall.

  The levels above describe the process boundary; the workspace mount is a deliberate hole
  through it, which is why containment of writes that reach the host is named here rather than
  assumed. A boundary can deny egress and hide every credential while still accepting writes the
  host later executes. A version-control config file can define commands, and one of them runs
  on a status call that looks read-only. Scope is deliberately write containment: read
  exposure is not covered at this level, and a copy-on-read workspace leaves reads fully open.

  The widening clause names a direction, because that is what generalizes. An additive policy
  layer, one whose installed components carry rules of their own, in the sense of extension
  permissions, admission control, or any engine that composes its rules from parts, meets `L2`
  only where a component's rules can subtract reachability and never add it. A surface where an
  installed component can add an allow rule the base policy denies is not `L2` however strict that
  base policy reads, because the run manufactures its own exception at install time: a component
  installed while the environment is being created can carry egress past a global default-deny.
  Until governance is configured so component rules can only narrow, the surface is not
  `L2`-capable.
- **`L3`: kernel-separated ephemeral environment.** Substrate classes (marked examples): a
  VM or microVM; a hosted ephemeral executor surface. Required where policy demands kernel
  separation. Two demands do: untrusted-provenance (`C5`) work, per the matrix's min-isolation
  column; and unattended GUI actuation, per the [routine catalog](../routines.md)'s access mapping
  rule. Synthetic input actuation drives the host's own input surface, which no process boundary
  contains. The second reaches classes that derive no work class at all, so it cannot be expressed
  through the min-isolation column.

  A boundary contains only what runs inside it. A protocol-connected tool surface the substrate
  brokers from the host, rather than one the contained process launches itself, keeps executing
  on the host at `L2` and `L3` alike.

## Axes

Two axes place a run on the ladder: **attendance** (whether a human is watching and able to
intervene) and **input provenance** (who can write to what the agent reads). Attendance
decides whether the `L2` unattended floor applies; input provenance decides whether the `L3`
kernel-separation bar applies.

## Rejected axis: trigger source

A trigger-source axis (externally signaled versus agent-internal) is recorded as rejected and
falsified: untrusted content reaches agent-internal runs through repository files,
dependencies, and fetched web content, not only through external signals, so a trusted
trigger source cannot lower the required isolation level.

## Unattended floor

`L2` is the uniform floor for any unattended run, regardless of work class, on every surface
except the [CI-lane surface](#ci-lanes-on-provider-hosted-runners); the matrix's
min-isolation column sets per-class floors at or above it. Per-command sandboxing (`L1`) is
not sufficient for unattended runs. It is an attended ergonomics tier, and treating it as an
autonomy tier is non-conforming.

## CI lanes on provider-hosted runners

A CI lane on a runner the CI provider hosts may run unattended without default-deny egress while
all five of these conditions hold (this marketplace records the decision as ADR 0049):

1. **Trusted actors only.** Only text from the operator and trusted bots reaches the lane prompt,
   checked per item against one centrally managed trusted-actor list.
2. **Same-repository change requests only.** No lane acts on a change request from a fork.
3. **Short-lived, scoped credentials.** Each job mints its own token, valid for at most one hour,
   scoped to what that job needs and revoked when the job ends. No long-lived write token reaches a
   model step, and no model step can write the required status check or change a workflow.
4. **A kill switch.** One org-level switch stops every lane without a code change; a switch the
   lane cannot read counts as off.
5. **Fresh runner per job.** No state carries from one job to the next.

A lane that fails any one condition is held to `L2`. A self-operated runner, a local lane and
every other surface keep `L2`, and `C5` work keeps `L3` on every surface.

## Fail-closed where L2 is unavailable

Where no `L2`-capable substrate exists on an execution surface, autonomous dispatch is
blocked for that surface and guided setup names the compliant paths. The
[CI-lane surface](#ci-lanes-on-provider-hosted-runners) is exempt only while all five of its
conditions hold. This rule is
fail-closed: silently degrading to a lower level is never conforming, because a silent degrade
leaks the trust loop the ladder exists to protect.

## Permission posture

`L1` is the attended ergonomics tier where per-action permission prompts remain the control;
at `L2` and above the whole-process boundary is the control and replaces per-action prompts.
