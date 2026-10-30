# The acceptance-criteria coverage prompt

Read this when the Brief's acceptance criteria are captured. It owns the coverage prompt, its
exemption from the open-question register, from the register gate and from the unattended ladder,
and what a non-interactive run does in its place. The EARS tags that may shape the same criteria are
[`ears.md`](ears.md).

## Coverage prompt. Always on, asked once

While capturing acceptance criteria, ask ONE question: are the criteria missing an
**unwanted-behavior** case (an `IF <trigger>, THEN <response>` criterion) and a **state-driven**
case (a `WHILE <state>, <response>` criterion)? One prompt covering both, never a per-criterion
interrogation, and **"neither applies" is a valid answer** that closes it for the session. This runs
whatever the acceptance-criteria format resolves to, and with no convention surface present at all;
it is a coverage check, not a format.

It is **not** a `Q<N>` decision. Never write it into the open-question register, never mark it
`blocked`, and never route it to `### Deferred questions`. The register gates the contract, and a
coverage check parked there would hold a lock hostage to a question that carries no decision. It
gets no row at ask-time even when it rides along inside a round, and asking it does not by itself
make the register exist, so it does not count as a round for SKILL.md "Emit checklist" either.

**It therefore does not bring the Step 3 register gate into scope by itself.** A synthesize-directly
run whose ONLY question was this prompt wrote no register, has nothing to gate, and skips the gate
exactly as a run that asked nothing does, rather than failing it ungradeable. Without this, that
path would ask a question it is forbidden to register and then trip a gate demanding the row. It is
never an item of the assumption sweep ([`assumption-sweep.md`](assumption-sweep.md)) either.

**The exemption covers this prompt and nothing else.** It is not a license for a question asked
beside it. A residue decision, a frontier round, a gap surfaced mid-synthesis, a `blocked` row from
an unattended run: any OTHER question is a register question as usual. It writes its row at
ask-time and brings the gate into scope, whether or not the coverage prompt was asked in the same
breath. One coverage check is exempt; a round that happens to contain one is not.

Per action: `me`, `auto` routed to Q&A, and the Mixed path ask it inside a round. `auto` routed to
synthesize-directly asks it as the sole residue question. `lock` skips it, because invoking `lock`
is the user saying stop asking, and reports it unexamined exactly as a non-interactive run does.
The prompt is never itself a criterion.

**On the page surface** it is a Notes question the user answers there: [`surface.md`](surface.md)
"Confirmation gate" posts it as a `note-reply` with `needsAnswer`, and it stays pinned on the
summary and counted in `N before wrap-up` until the user answers in Notes. The restate refuses an
acceptance line that asks the user something. When the user confirms or wraps up without answering
it, the export reports it under the Brief's `### Captured assumptions` as
`- asked in Notes, not answered: <the prompt>`, which stands for "unwanted-behavior and
state-driven coverage went unexamined"; tell the user so in the wrap-up.

## Non-interactive runs skip the ask and say so

A run with nobody to answer, a dispatched worker, a forked subagent, a headless invocation, or any
caller that declared the run unattended, **SKIPS** the ask instead of blocking on it, and the
session's returned summary states that **unwanted-behavior and state-driven coverage went
unexamined**. Write the same line into the Brief's `### Captured assumptions` so it outlives the
summary. A prompt nobody can answer must not stall the run and must not silently vanish.

**The prompt is exempt from the unattended ladder** ([`loop.md`](loop.md) "Unattended path"): never
a `blocked` register row, never a `### Deferred questions` entry, and never a blocker that stops the
run. It exempts itself and nothing else.

**That line is the coverage note and nothing else.** It records that a check went unrun. It is never
a place to park a decision, it satisfies no part of the auto-guard, and it changes nothing about the
unattended ladder: a decision genuinely the user's is still recorded `blocked`, still written to
`### Deferred questions` with **arbiter: USER-RESERVED**, and still named as a blocker. Capturing a
user's decision as an assumption is the failure the auto-guard exists to prevent, and no line here
licenses it.

The unattended condition is **declared by the caller, never sniffed**, the same rule the auto-guard's
unattended path states. There is no supported way for a session to observe that it is
non-interactive, so never read an environment variable to decide this.
