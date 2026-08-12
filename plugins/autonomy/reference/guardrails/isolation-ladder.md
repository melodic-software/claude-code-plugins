# Isolation ladder

Normative leaf of the [guardrail contract](../guardrails.md): the tool-agnostic isolation
ladder the matrix's min-isolation column keys on. Levels are contract vocabulary. Substrate
instances are org-supplied through the security binding per the guided-setup pattern — this
document names substrate CLASSES as marked examples only, never an instance list.

## Levels

- **`L0` — worktree + VCS permissions only.** No OS boundary: the working tree and
  version-control permissions are the only containment. Attended interactive use only.
- **`L1` — per-command OS sandbox.** The sandbox wraps shell-command execution only; file
  tools, hooks, and protocol-connected tool surfaces still execute on the host. An attended
  ergonomics tier — NOT an autonomy tier.
- **`L2` — whole-process OS-enforced boundary with default-deny egress, credential
  protection, contained workspace host-writes, and policy nothing the run can install may
  widen.** The MINIMUM for any unattended run.
  Free-path substrate classes (marked examples, not an instance list): a whole-process
  OS-sandbox wrap; a container with a default-deny egress firewall.

  The levels above describe the PROCESS boundary; the workspace mount is a deliberate hole
  through it, which is why containment of writes that reach the HOST is named here rather than
  assumed. A boundary can deny egress and hide every credential while still accepting writes the
  host later executes — a version-control config file is a command key ring, and one of its keys
  fires on a read-only-looking status call. Scope is deliberately WRITE containment: read
  exposure is not covered at this level, and a copy-on-read workspace leaves reads fully open.

  The widening clause names a DIRECTION, because that is what generalizes. An additive policy
  layer — one whose installed components carry rules of their own, in the sense of extension
  permissions, admission control, or any engine that composes its rules from parts — meets `L2`
  only where a component's rules can subtract reachability and never add it. A surface where an
  installed component can add an allow rule the base policy denies is not `L2` however strict that
  base policy reads, because the run manufactures its own exception at install time; the failure is
  measured, not hypothetical — a component installed while the environment was being created
  carried egress past a global default-deny and origin data flowed. Until governance is configured
  so component rules can only narrow, the surface is not `L2`-capable.
- **`L3` — kernel-separated ephemeral environment.** Substrate classes (marked examples): a
  VM or microVM; a hosted ephemeral executor surface. Required where policy demands kernel
  separation — untrusted-provenance (`C5`) work.

## Axes

Two axes place a run on the ladder: **attendance** (whether a human is watching and able to
intervene) and **input provenance** (who can write to what the agent reads). Attendance
decides whether the `L2` unattended floor applies; input provenance decides whether the `L3`
kernel-separation bar applies.

## Rejected axis: trigger source

A trigger-source axis (externally signaled versus agent-internal) is RECORDED AS REJECTED —
falsified: untrusted content reaches agent-internal runs through repository files,
dependencies, and fetched web content, not only through external signals, so a trusted
trigger source cannot lower the required isolation level.

## Unattended floor

`L2` is the uniform floor for any unattended run, regardless of work class; the matrix's
min-isolation column sets per-class floors at or above it. Per-command sandboxing (`L1`) is
not sufficient for unattended runs — it is an attended ergonomics tier, and treating it as an
autonomy tier is non-conforming.

## Fail-closed where L2 is unavailable

Where no `L2`-capable substrate exists on an execution surface, autonomous dispatch is
BLOCKED for that surface and guided setup names the compliant paths. This rule is
fail-closed: silently degrading to a lower level is never conforming — a silent degrade leaks
the trust loop the ladder exists to protect.

## Permission posture

`L1` is the attended ergonomics tier where per-action permission prompts remain the control;
at `L2` and above the whole-process boundary is the control and replaces per-action prompts.
