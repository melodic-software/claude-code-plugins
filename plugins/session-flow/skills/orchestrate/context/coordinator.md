# Coordinator rules

Loaded by the `coordinator [<area>]` action. They hold for the whole session once it is armed.
Each rule uses what this session can do, what the repository already has, and what the user asked
for. Where a named capability is absent, the rule's fallback applies; nothing here installs one.
State these rules create lives where the action row says all state lives: the tracker when the
area has one, otherwise a durable file the repository already keeps for the area. A context loss
or account rotation then loses none of it.

1. **Standing orders as numbered lines.** Write the user's standing orders for the area as
   numbered lines labeled `Order 1`, `Order 2`, ..., one order per line, in the user's words
   where they gave any, so they never collide with the imperatives' numbers. Restate the full
   list, unchanged, at the top of every worker brief you spawn and every message that resumes a
   worker or a fresh session. A worker never has to infer an order from history it did not
   inherit. When the user changes an order, edit its line and keep its number.
2. **Park each human approval as an item.** When work reaches a step only the user can approve,
   stop that branch of work and park it with three parts:
   - **Decision:** what the user is asked to approve, in one sentence.
   - **Recommendation:** what you recommend and its basis.
   - **If unanswered:** what happens while it waits (which work stays blocked, what carries on,
     and any date after which the choice no longer helps).

   Record the item where state lives (above) and report it when it is parked. Other work carries
   on around it. A tick reports it again only when its state changes; a resume re-lists every
   open item once.
3. **The loop tick checks children by what they did.** Run each tick on the repetition the
   session has (`/loop` when available; otherwise the user re-enters it). A tick reads each
   worker's evidence: commits and branch heads, pull request and check state, tracker changes,
   output files. A worker's own summary of its progress is not evidence. When nothing changed
   since the last tick, the tick sends no catch-up: at most one line saying nothing changed. When
   something changed, report only what changed and any newly parked item.
4. **One writer per shared surface.** Each shared surface (a branch, a file, a tracker item, a pull
   request) has exactly one worker that writes it, from the brief that assigns it until that
   worker returns or is retired. Never give a second worker a surface while the first holds it.
   When a tick sees friction in the environment (a missing tool, a recurring mistake, a step that
   costs more than it should), record one environment-improvement note in the corrections buffer:
   `/corrections:codify note "<observation>"` when that plugin is enabled. Without it, put the
   note in the next report that has a change, so a quiet tick stays quiet.
