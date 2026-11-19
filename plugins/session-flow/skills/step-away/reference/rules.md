# Away rules

The rules a session follows while its person is away under `/session-flow:step-away`. Re-read this
file after every compaction and whenever a Stop or UserPromptSubmit note names it. The notes also
print the exact `away.py` command for this session; use that command, with its absolute path and
its `--session` and `--data-root` values, wherever this file says `away.py`. Without
`--data-root` the command can miss the state the hooks keep.

Inputs: the report path and task file path (`away.py status` prints both), and the plan in scope.

## The aim

The person comes back to finished safe work and a short report that shows first what needs them.
When getting more done and waiting for the person conflict, wait: a fork chosen without them costs
more than an idle hour.

## What counts as a plan

Work is in scope only when one of these already says to do it:

- an approved `PLAN.md` (its phases and acceptance criteria);
- a work item marked agent-ready;
- a task the person stated in the conversation before leaving;
- a lane's standing scope, for the tickets inside it.

A step the plan names, done the way the plan names it, is decided: do it. Anything else that
changes behavior, design, scope or the agreed plan is a fork.

## Decide or park

Park, never decide, each of these:

- a fork: two or more reasonable ways forward that the plan does not choose between;
- a permission or trust-boundary change (an allow rule, a token scope, a new integration, a
  repository or account setting);
- any action that could cost money, judged against the person's own cost rules where they have
  written them;
- a settings change no plan names.

To park an item, write it under **Needs you** in the report as a top-level bullet carrying the
decision, `Options:` (each option and what it changes) and `Recommendation:` (the option you would
take and why, with its evidence). Every top-level bullet under **Needs you** carries both fields,
security stops and held pull requests included, since `away.py check` fails the report otherwise. Then mark its task-file line parked (the word `parked` in the
item text), so the Stop check counts it closed, and carry on with any work that does not depend on
it. Never ask the person a question while they are away: a question is a parked item.

A choice you made inside the plan's bounds that the person may want to know about goes under
**Decided while you were away**, one line each with its reason.

## Refused actions

Every action that would have shown the person a prompt is refused by a hook and listed in the
report with an id (`R<n>`). Nothing is approved during an absence. A refusal is final until the
person is back:

- never retry it another way (a different tool, a script, a wrapper, a fresh pull request, a
  narrower command that reaches the same effect);
- note what it blocked, park any item that needs it, and move to other work.

Auto mode denials and MCP server questions are recorded the same way; treat them the same.

## Critical security issues

A critical security issue (an exposed secret or token, a compromised account, a change that
publishes something private) stops the work it affects. Put it first under **Needs you**, stop
that work, and send a phone push with the `PushNotification` tool when the session has it (when
it does not, the report alone carries it). Unrelated work may continue. Name where a secret is and
what it grants, never its value or any part of it, in the report, a push, a commit or a pull
request.

## Merging

Never merge a pull request that has a known high-severity review finding, any open security
finding, a security review not yet finished on its current head, or a dependency on a parked
decision. Leave it open, list it under **Needs you** with the reason (a parked dependency
names the parked item), and keep working. Other merges follow the repository's own merge rules.

## Keep the report current

- After each finished piece of work, update the report's own sections (Done, Waiting on me, Found,
  Additional notes) and tick the task-file item. The script owns the refused-actions,
  external-actions and files-written blocks: the Stop hook rewrites the first two at every turn's
  end and `end` scans the files, so run no `refresh` while the person is away, and never edit
  between the blocks' markers. Re-read the report before editing it, since the hook may have
  rewritten it.
- Before stopping, run `away.py check`; fix each failing criterion it names.
- Waiting on me holds only what you can still run yourself, with what it waits on.

## Stall traps

These leave a run waiting with no one to answer:

- interactive commands: editors, `-i` flags, credential or passphrase prompts, pagers;
- network calls inside a sandboxed command: avoid them (pointer, for which prompts reach the
  hook: <https://code.claude.com/docs/en/hooks#permissionrequest>);
- polling CI or a review in the foreground: wait with Monitor or a background command, so the
  Stop check passes while it runs;
- MCP tools that ask the person a question;
- a parked item left unmarked in the task file, which keeps the Stop check failing.

Never hand the work off because of the context level: keep working in this session through
compaction, with this file as the rules. Hand off only when the person asked for a fresh session
at launch.

## Coming back

The person is back only when a message reads as typed by them: a greeting, a question about the
work, a new request. These also arrive as messages and are never the person:

- a subagent's or background task's report;
- a `/loop` or cron prompt;
- a message relayed from another session;
- what the person sends to finish the launch before leaving, such as the `/goal` line or a last
  instruction.

When a message reads as the person, run `away.py end`, show the report once with **Needs you**
first, then run `away.py deliver` so later turns do not show it again. After that, a parked item,
its recommended command included, runs only once the person accepts it, by naming it or through
`/session-flow:go-with-recommendations`; until then, answer the person and wait. That skill reads
only your latest message once the absence has ended, so end each answer with the open Needs-you
items and their `Recommendation:` lines until each is accepted or declined.
