# audit-pass — the `/doctor` handoff

`/doctor` owns the `CLAUDE.md` trim-and-migrate half of a configuration pass. This skill deliberately
builds no replacement for it. What follows is the prerequisite contract, the absence classification,
and why the handoff is an operator instruction rather than a dispatch.

## It is never dispatched

`/doctor` "reports what it finds … then proposes fixes it applies only after you confirm"
([debug your configuration](https://code.claude.com/docs/en/debug-your-config), verified 2026-07-24).
An unattended run cannot answer that prompt, so driving it from this pass would either hang the run
or push it toward answering a confirmation on the operator's behalf.

**The handoff is therefore an operator instruction.** The pass finishes its own phases, then tells
the operator to run `/doctor` themselves. Nothing in this pass invokes it, waits on it, or drives it.

**What it does not do is refuse the result the operator brings back.** "Never parses its output as a
lane result" would make the `delegated` tier unreachable — the lane could never leave `open`, and
this file's own promise that `/doctor`'s output lands in `delegated` would be unkeepable. The
distinction that carries the weight is *who decides*, not *whether the pass reads*: the pass never
invokes `/doctor`, never waits on it, and never answers a confirmation on the operator's behalf; when
the operator returns its output through `--resume`, the pass records that output as the lane's
findings and terminates the lane `handed-back`. An operator handing a result back **is** the operator
acting, which is what the handoff exists for — treating their return as unreadable would strand the
outcome this phase was built to capture.

## Presence, and what is actually verified

Checking a version number alone is not a presence check. The pass reports **which** prerequisite
failed rather than a bare "unavailable" — and it distinguishes what official documentation confirms
from what it does not.

**Verified against current official docs (2026-07-24).**

1. **Version floor — Claude Code v2.1.206 or later.** "The `CLAUDE.md` trim check requires Claude
   Code v2.1.206 or later" ([debug your configuration](https://code.claude.com/docs/en/debug-your-config);
   repeated on [memory](https://code.claude.com/docs/en/memory)). Below the floor, the capability
   this pass hands off is not the capability that exists.
2. **The v2.1.205 behavior cutover.** "Before v2.1.205, `/doctor` opened a read-only diagnostics
   screen and pressing `f` sent the report to Claude to fix" (same page). A pass that assumes the
   pre-cutover shape on a current install is checking for the wrong thing.

**Suppression channels — treat as UNVERIFIED and probe, never assume.** Two further ways an install
can lack `/doctor` were carried in from this skill's design phase and are **not documented on the
current official pages** — `DISABLE_DOCTOR_COMMAND` does not appear in the
[environment variables](https://code.claude.com/docs/en/env-vars) list, and no `skillOverrides` key
appears in [settings](https://code.claude.com/docs/en/settings) (both checked 2026-07-24). They may
be real but undocumented, or stale.

So the pass **detects absence rather than predicting it**: it checks whether `/doctor` actually
resolves in this environment, and reports the outcome. If it does not resolve while the version floor
is met, the run says so and names these two as the suspected — unconfirmed — causes, rather than
asserting either as the reason.

**Recheck trigger:** any Claude Code minor release, or any change to how bundled skills are
suppressed. Re-verify against current official documentation before treating a failed prerequisite as
authoritative — a stale floor would report a present capability as missing.

## Absence classification: optional capability

Per the prerequisites-and-failure-behavior rules, absence here is **required for an optional
feature**, not required for correctness. So the pass:

- **warns visibly**, naming `/doctor` as the missing capability and which prerequisite failed;
- **states what goes unchecked** — the whole `CLAUDE.md` trim-and-migrate half, for which this work
  deliberately builds no replacement;
- **continues** with the documented reduced result, and completes normally.

It never degrades silently, and it never substitutes a local approximation of the trim. Reporting the
gap is the floor the design boundary sets; a silently skipped feature is a defect.

## Its output is the delegated tier

When the operator does run `/doctor` and brings its output back, it lands in the report's `delegated`
section and **carries no idempotence property at all** — neither the derived tier's exact equality
nor the judged tier's stability tolerance.

The reason is structural rather than a matter of trust: `/doctor` is a prompt-based bundled skill,
and a prompt-based delegate cannot contribute to a determinism gate. Including it in either property
would make the gate report a stability the run does not have.
