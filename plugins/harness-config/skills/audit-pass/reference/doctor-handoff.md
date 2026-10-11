# audit-pass: the `/doctor` handoff

`/doctor` owns the `CLAUDE.md` trim-and-migrate half of a configuration pass. This skill deliberately
builds no replacement for it. What follows is the prerequisite contract, the absence classification,
and why the handoff is an operator instruction rather than a dispatch.

## It is never dispatched

`/doctor` asks the operator before it changes anything. An unattended run cannot answer that prompt,
so driving it from this pass would either hang the run or push it toward answering a confirmation on
the operator's behalf.

- **Pointer**: when deciding whether `/doctor` can run unattended, fetch
  [skills: check your setup with /doctor](https://code.claude.com/docs/en/skills#check-your-setup-with-/doctor)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: that section says `/doctor` applies a fix without asking first.

**The handoff is therefore an operator instruction.** The pass finishes its own phases, then tells
the operator to run `/doctor` themselves. Nothing in this pass invokes it, waits on it, or drives it.
`/doctor prompt-audit` is handed off the same way, as an operator-run instruction-file audit this
pass never dispatches.

- **Pointer**: for its scope, write posture and version floor, see
  <https://code.claude.com/docs/en/memory#audit-your-instruction-files>.
- **As of**: 2026-10-01
- **Recheck trigger**: that section changes its write posture or version floor, or moves.

**What it does not do is refuse the result the operator brings back.** "Never parses its output as a
lane result" would make the `delegated` tier unreachable. The lane could never leave `open`, and
this file's own promise that `/doctor`'s output lands in `delegated` would be unkeepable. The
distinction that carries the weight is *who decides*, not *whether the pass reads*: the pass never
invokes `/doctor`, never waits on it, and never answers a confirmation on the operator's behalf; when
the operator returns its output through `--resume`, the pass records that output as the lane's
findings and terminates the lane `handed-back`. An operator handing a result back **is** the operator
acting, which is what the handoff exists for. Treating their return as unreadable would strand the
outcome this phase was built to capture.

## Presence, and what is actually verified

Checking a version number alone is not a presence check. The pass reports **which** prerequisite
failed rather than a bare "unavailable", and it distinguishes what official documentation confirms
from what it does not.

1. **Version floor.** The `CLAUDE.md` trim check this pass hands off has a version floor, and
   `/doctor`'s shape changed across releases before it. Compare the installed version with the
   floor the pointer states; below it, the capability this pass hands off is not the capability
   that exists, and a pass that assumes the current shape on an older install is checking for the
   wrong thing.
   - **Pointer**: when checking the floor, fetch
     [memory: my CLAUDE.md is too large](https://code.claude.com/docs/en/memory#my-claude-md-is-too-large)
     live.
   - **As of**: 2026-10-11
   - **Recheck trigger**: that section moves, raises or drops the floor.
2. **`DISABLE_DOCTOR_COMMAND`: documented.** The variable's row is on the environment-variables
   page again, so it is a documented suppression channel, and its scope is the row's: read which
   surface it hides, and which it leaves alone, from the row rather than from here.
   - **Pointer**: when naming it as a cause, fetch the `DISABLE_DOCTOR_COMMAND` row of
     [environment variables: variables](https://code.claude.com/docs/en/env-vars#variables) live.
   - **As of**: 2026-10-11
   - **Recheck trigger**: the row leaves the table, as it did between earlier fetches, or changes
     which surface it hides.

**Suppression channels: one documented, one documented but silent on bundled skills.**
`skillOverrides` is a documented settings key that reaches some skill sources and not others. The
skills page names which, and does not say whether it reaches a bundled skill such as `/doctor`, so
its effect on the handoff is UNVERIFIED; probe rather than assert.

- **Pointer**: when naming `skillOverrides` as a cause, fetch
  [skills: override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: that section states whether an override reaches a bundled skill.

So the pass **detects absence rather than predicting it**: it checks whether `/doctor` actually
resolves in this environment, and reports the outcome. If it does not resolve while the version floor
is met, the run says so and names these channels as the suspected causes, `DISABLE_DOCTOR_COMMAND`
and a `skillOverrides` entry naming the skill (documented for some skill sources, unverified for
bundled ones), rather than asserting either as the reason. Detecting beats predicting either way: the variable's presence in the list says an operator
*could* have set it, never that they did.

**Recheck trigger:** any Claude Code minor release, or any change to how bundled skills are
suppressed. Re-verify against current official documentation before
treating a failed prerequisite as authoritative. A stale floor would report a present capability as
missing, and the entry corrected above shows a stale *absence* claim reads exactly like a fresh one.

## Absence classification: optional capability

Per the prerequisites-and-failure-behavior rules, absence here is **required for an optional
feature**, not required for correctness. So the pass:

- **warns visibly**, naming `/doctor` as the missing capability and which prerequisite failed;
- **states what goes unchecked**: the whole `CLAUDE.md` trim-and-migrate half, for which this work
  deliberately builds no replacement;
- **continues** with the documented reduced result, and completes normally.

It never degrades silently, and it never substitutes a local approximation of the trim. Reporting the
gap is the floor the design boundary sets; a silently skipped feature is a defect.

## What `/status` and `claude doctor` now carry

This pass still cannot observe three facts, and it does not grow a local approximation of them.
`/status` and `claude doctor` report them, each from a version the pointers state:

- whether organization policy loaded, from which source, and why it did not;
- a policy-helper refresh failure;
- which credential is in use when more than one is configured.

Hand the operator those commands. Do not infer the answers from the local managed files this pass
reads.

- **Pointer**: when handing the operator those commands, fetch
  [managed settings: read the source in /status](https://code.claude.com/docs/en/managed-settings#read-the-source-in-/status)
  and
  [managed settings: keys only a managed source can set](https://code.claude.com/docs/en/managed-settings#keys-only-a-managed-source-can-set)
  live. Those sections cover the policy line only; this file has found no docs section for the
  helper-failure or credential lines as of 2026-10-11, so hand them to the operator as lines to look
  for, not as documented output.
- **As of**: 2026-10-11
- **Recheck trigger**: the `Organization policy` line moves off `claude doctor` or `/status`, or a
  docs section starts covering the helper-failure or credential lines.

## Its output is the delegated tier

When the operator does run `/doctor` and brings its output back, it lands in the report's `delegated`
section and **carries no idempotence property at all**, neither the derived tier's exact equality
nor the judged tier's stability tolerance.

The reason is structural rather than a matter of trust: `/doctor` is a prompt-based bundled skill,
and a prompt-based delegate cannot contribute to a determinism gate. Including it in either property
would make the gate report a stability the run does not have.
