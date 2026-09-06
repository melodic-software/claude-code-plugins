---
description: "Hold the user's hand through a long multi-step job. Partition the remaining work into phases and present ONLY the current one, never the phases after it beyond a one-line 'Phase 1 of 8' count. Each phase names where to be, numbered steps with exact commands, the expected output, the common failure, who performs each step, and the exact reply that advances. Once invoked, this holds for the rest of the session. Use when: 'hold my hand', 'walk me through this', 'one step at a time', 'one phase at a time', 'don't show me the next step yet', 'guide me through all of this', 'exact steps', 'hand-hold'. This is a STANDING posture that withholds later steps: adhd:shape sets action-first formatting for every response and shows the whole list, adhd:clarify reshapes one dense message already on screen, wizard:generate writes a bash script the human runs with no assistant in the loop, and session-flow:workflow routes to the next stage without scripting its steps."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Standing posture. Phase the work, present one phase at a time, wait for the advancing reply
---

# Hold my hand

Once invoked, this is a standing instruction for the rest of the session. Take
the work that remains, cut it into phases, and present **one phase at a time**.
The user never sees Phase 2 until Phase 1 is presented and done.

## A declared species in this plugin: NOT a corrector

Every corrector in this plugin re-anchors a standing discipline through the
re-anchor/audit/correct loop, and `wait-what` is a one-shot repair. This skill
is a third species: a **standing session posture** over how future work is
delivered. It audits nothing and finds nothing. It changes the shape of every
subsequent response until the session ends or the user cancels it.

It carries no `discipline-batch` tier, on purpose. A batch sweep must never
impose a delivery posture the user did not ask for.

## Partition the work into phases

A phase is a contiguous run of steps that ends at a point the user can confirm.
Cut on the confirmable boundary, not on an even step count: a phase ends where
something is observably true (a file exists, a service answers, a page loads).

State the count once, on a single line, so the user knows the shape of the job
without reading ahead:

```text
Phase 3 of 8: Install the runner on the build machine
```

Never list the later phases. Not as a preview, not as a table of contents, not
as a "here is where we are going" paragraph, and not as a task-ledger dump the
user reads over your shoulder. The count is the only forward information.

When the work turns out to need more phases than the first estimate, say so in
one line ("this is now 10 phases, not 8") and continue. Silently growing the
count is worse than restating it.

## What every phase states

Each phase carries all six of these. A phase missing one of them is not ready
to present.

1. **Where.** The machine, the kind of terminal (PowerShell, bash, a browser
   tab, a physical console), whether it must be elevated, and the working
   directory.
2. **Numbered steps.** One action per numbered step, in the order they run.
3. **The exact command**, in a fenced block, with real values substituted. Not
   a template with placeholders the user must fill in from memory.
4. **The expected output** after each command, so the user can tell success
   from failure without asking.
5. **The common failure and its repair.** The one that actually happens, with
   what to do about it.
6. **The exact reply that advances.** Write it as a literal the user can copy:

   ```text
   When those two steps are done, tell me: `phase 3 done`
   ```

## Mark who performs each step

Do everything you can do yourself **before** presenting the phase, then present
only what is left. The user's steps are the ones you cannot perform:

- an action needing elevation or credentials you do not hold;
- an action on another machine, a hardware console, or a physical device;
- a click in a vendor dashboard or a third-party web console;
- a decision or an approval that is legally or operationally theirs.

Label every step with its performer. When a phase turns out to contain nothing
the user must do, run it and report the result rather than presenting steps to
someone who has nothing to perform.

## Wait, then check, then advance

Stop after presenting a phase. Do not begin the next one because the work looks
obvious or because waiting feels slow.

When the advancing reply arrives, check what is mechanically checkable before
presenting the next phase: run the probe, read the file, query the API or the
forge for the object's state. Report what the check returned.

When a check comes back wrong, present a **repair sub-phase** (`Phase 3a`), not
Phase 4. A repair sub-phase has the same six parts as any phase. Return to the
main sequence only after the repair's own check passes.

## Write the steps in full sentences

Every step is a complete sentence with its conjunctions, articles, and
prepositions intact, even when a compression or terse-output mode is active in
the session. Ordered operational steps are the one place compression is unsafe:
a dropped conjunction changes whether two clauses are sequential, conditional,
or alternative, and the reader executes the wrong one. Terseness applies to how
many steps there are, never to the grammar inside a step.

## One thing per phase

Ask at most one question in a phase, and never present a menu. When a choice
arises, make it, and record it in one line:

```text
Decision: using PowerShell rather than WSL, because the runner service is registered on Windows.
```

A user who asked to be hand-held asked to stop making decisions. Surfacing
options returns the load they handed over. The exception is a decision that is
theirs by right (cost, access, data, a legal or safety consequence): those are
raised as the phase's single question.

## Mirror the phases into a task ledger

When task tools are available in the session, mirror each phase as one task and
keep its state current as phases complete, so the user can see progress without
scrolling. Ledger entries for unpresented phases carry the phase number and
nothing that reveals their steps. When no task tools are available, keep the
same numbered list in your replies.

## Boundaries

- **Standing, not one-shot.** The posture holds until the session ends or the
  user cancels it. It is not a single formatted answer.
- **Not action-first formatting.** `/adhd:shape` shapes every response
  action-first and shows the user the whole list; this posture deliberately
  withholds the rest of the list.
- **Not a message repair.** `/adhd:clarify` reshapes one dense message already
  on screen. `/discipline:wait-what` re-pitches a message that did not land.
  Neither one phases the remaining work.
- **Not a generated script.** `/wizard:generate` writes a bash script the human
  runs alone, with no assistant in the loop. This posture keeps the assistant in
  the loop between every phase, which is what makes the per-phase check possible.
- **Not stage routing.** `/session-flow:workflow` says which stage comes next;
  it does not write the commands for that stage.
- **Does not change what the work is.** Phasing is a delivery shape. It adds no
  steps, removes none, and reorders only where a dependency requires it.

## Gotchas

- The most common failure is leaking the plan. A phase that opens with "next
  we'll do X, Y, and Z, but first ..." has already shown the user everything
  they asked not to see. The count is the only forward-looking line.
- The second most common failure is presenting steps the assistant could have
  performed. Check what you can run yourself before writing the phase, not
  after the user reports that a step was yours to do.
- Advancing on a bare acknowledgement ("ok", "thanks") skips the check. Wait
  for the advancing reply the phase named, or ask for it once.
- A phase whose steps have no confirmable end produces an advancing reply that
  proves nothing. Move the boundary to the nearest observable state instead of
  accepting an unverifiable "done".
- Long phases defeat the purpose. When a phase runs past roughly seven steps,
  it is two phases with a confirmable boundary hiding in the middle.
