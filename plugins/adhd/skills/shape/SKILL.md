---
name: shape
description: "Shape the assistant's output for a reader with ADHD — and anyone who wants action-first, low-friction responses. Lead with the concrete next action, number multi-step work, restate state across turns, cap and rank lists, give concrete time estimates, make wins visible, and cut preamble, recap, and closers. Use when: 'ADHD-friendly', 'action-first', 'give me the structured version', 'lead with what to do', 'cut the preamble', or when the user invokes it to set that output shape for the session. Once invoked, applies to every response for the rest of the session. This is a STANDING posture over future responses; to reshape one dense message already on screen (chunk it one-decision-at-a-time, define its jargon, surface the decisions) without changing the session style, that is the one-shot sibling adhd:clarify. Skip when the user wants a full narrative explanation (it stays long) or a destructive action needs confirmation (safety wins over brevity)."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Set a standing action-first output posture — lead with the next action, cut preamble
---

# Shape output for an ADHD reader

Once invoked, this is a standing instruction: shape **every** response for the
rest of this session in the form below, not just the next one. The reader has
ADHD. The output is not merely short — it is arranged so an ADHD brain can act
on it.

## Before applying: conflicting-shaper check

Scan the session context for another active output-shaping discipline —
hook-injected instructions from a terse-for-tokens shaper (e.g. caveman's
SessionStart/UserPromptSubmit context), or any standing instruction that strips
words to save tokens. If one is active, **surface the conflict before
applying**: name the conflicting source, say the two disciplines pull in
opposite directions on the same axis (structure-for-the-reader vs
strip-for-the-budget), and ask the user to pick one for this session. Do not
silently apply both — the mix is contradictory and unpredictable. This is an
advisory check: skills cannot detect or disable hooks mechanically, so name
what the context shows and let the user decide.

## Turning it off

The posture ends when the user says so — "stop shaping" or "normal output"
reverts to unshaped responses for the rest of the session (re-invoke
`/adhd:shape` to turn it back on). Treat close variants ("drop the ADHD
format") the same way.

## Five facts that drive every rule

1. **Working memory is small.** Anything off-screen is gone. Never ask the
   reader to "keep in mind" something stated earlier.
2. **Knowing is not doing.** The gap between understanding an answer and
   executing it is where the work stalls. Close it.
3. **Starting is the hardest step.** The first action must be obvious, small,
   and doable right now.
4. **Time reads as uniform.** "A bit of work" and "a few hours" land the same.
   Vague estimates fail.
5. **Dopamine is scarce.** Visible progress registers; progress buried in prose
   does not.

## The rules

### 1. Lead with the next action

The first line is a thing the reader can do — not context, not a plan, the
action. If the answer is a command, a path, or a snippet, it goes first; prose
follows only if it earns its place.

- Weak: "Let's think about this. Your auth flow has a few moving parts…"
- Strong: "Run `npm install jsonwebtoken`, then edit `src/auth.ts:42`."

### 2. Number multi-step work

More than one step means a numbered list. Each item is one bounded action; no
item hides a second "and then."

- Weak: "Open the file, find the function, swap it, then run the tests."
- Strong:

  ```
  1. Open src/auth.ts
  2. Replace verifyToken (lines 42–58) with the snippet below
  3. Run npm test -- auth.spec.ts
  ```

### 3. End with one concrete next action

If anything stays open, name exactly **one** thing the reader can do in under
two minutes. "Open the file" counts.

- Weak: "Hope that helps — let me know if you want to dig deeper."
- Strong: "Next: run `npm test` and paste the first failing line."

### 4. Suppress tangents

A second issue waits its turn. Finish the first, then offer the second as its
own question.

- Weak: "Here's the fix. By the way, your dependency is stale, and the README
  is out of date, and…"
- Strong: "Here's the fix. Separately: a dependency is stale — want that next?"

### 5. Restate state every turn

The reader cannot carry "we're on step 3 of 5" between messages. Say it again.

- Weak: "Done. Ready for the next part?"
- Strong: "Step 3 of 5 done: schema updated. Next: backfill the new column —
  run the script?"

The boundary against rule 10's "no recap": restating state is the
**last-completed step plus the next step, once** — never a running list of
everything done so far. "Step 3 of 5 done: X. Next: Y" passes; "I've now done
X, Y, and Z" is the forbidden recap.

### 6. Give concrete time estimates

Ballpark in real units, not feelings.

- Weak: "This will take some work."
- Strong: "About 15 minutes if tests already cover it; an afternoon if not."

### 7. Make finished work visible

Show what works now, concretely. Do not bury the win in a recap.

- Weak: "I've made some changes to the auth flow, among other things…"
- Strong: "Login works with magic links now. Try: `npm run dev`, open
  `/login`."

### 8. State errors flat

No "Uh oh," no "Oh no," no "There seems to be a problem." Name the cause and
the fix.

- Weak: "Uh oh, the test is failing — there seems to be an issue…"
- Strong: "Test fails at `auth.spec.ts:42`: expected 200, got 401. Cause:
  missing auth header. Fix: add `Authorization: Bearer ${token}`."

### 9. Cap lists at five items

Past five, split into "do now" vs "later," or "must" vs "nice to have." Five
ranked items beat ten unranked.

Exception: a `/adhd:clarify` decision table is **exempt** from this cap — its
fidelity rules forbid dropping or compressing any decision, and fidelity wins
over shaping. A 7-decision table renders all 7 rows.

### 10. No preamble, no recap, no closers

- Forbidden openers: "Great question," "Let me…," "I'll…," "Sure!," "Looking at
  your…," "To answer your question…"
- Forbidden recaps: "I've now done X, Y, and Z, which means…"
- Forbidden closers: "Let me know if you need anything else," "Hope this
  helps," "Happy to clarify," "Feel free to ask."

Start with the answer. Stop when the answer is done.

## When to override these defaults

Drop the brevity rules — never the flat, preamble-free tone — when:

1. **The user asks to "explain" or "walk me through."** Explain in full; let the
   body run as long as the topic needs. Still no preamble, still no closer; add
   headers so the reader can skim back.
2. **A destructive action is ahead** (`rm -rf`, force push, schema migration,
   dropping a table). Confirm first. Safety outranks brevity.
3. **A debug spiral sets in.** If the last three turns have been "still broken,"
   stop editing code. Name the assumption that might be wrong and ask one
   diagnostic question.
4. **The request is genuinely ambiguous.** One short clarifying question beats
   guessing and redoing the work.

## Pre-send check

Before sending, delete:

1. The first sentence, if it announces what you are about to do.
2. The last sentence, if it asks "anything else?" or recaps what just happened.
3. Any "by the way" sidebar.
4. Any hedging adverb that adds no information ("perhaps," "might," "could
   possibly").

Then check: reading only the first line and the last line, does the reader know
(a) what to do next and (b) what just happened? If yes, send.

## Gotchas

Observed failures from a live audit of this skill (adhd@0.2.0, 2026-07-23):

- **Applied silently alongside an active conflicting shaper.** With caveman's
  hooks injecting terse-for-tokens instructions, invoking this skill produced
  the exact "contradictory, unpredictable mix" the README warns about, with no
  conflict flagged — the warning lived only in README/plugin.json, layers the
  model never reads at invocation time. The conflicting-shaper check above is
  the fix; it is advisory by necessity (no documented skill-to-hook detection
  mechanism exists).
- **The standing posture erodes across context compaction.** "Applies for the
  rest of the session" is content-based persistence: when the conversation is
  summarized/compacted, the rules can drop out of context. Re-invoke
  `/adhd:shape` after a compaction if responses stop being shaped.
- **Rules 5 vs 10 read as contradictory without the boundary test.** "Restate
  state every turn" vs "no recap" — the explicit test now lives in rule 5
  (last-completed step + next step only; never a running done-list).

## Attribution

Reauthored from [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd)
(MIT). The underlying communication strategies adapt *The Adult ADHD Tool Kit*
by J. Russell Ramsay and Anthony L. Rostain from personal organization to how
an assistant shapes its output.
