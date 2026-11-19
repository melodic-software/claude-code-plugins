---
description: "Run this session alone while the person is away (AFK): refuse prompts, park their decisions, and keep a return report."
argument-hint: "[until <time>|<trip>|fresh session] [scope ...]"
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: session
  summary: Run the session alone while the person is away and report on return
---

**Arguments.** `[until <time>|<trip>|fresh session] [scope ...]`. e.g., /step-away, /step-away until 7am, /step-away driving all day, /step-away fresh session finish the parser plan

# Step away

The person is leaving and wants to come back to finished safe work and a short report that shows
first what needs them. When the two conflict, never choosing at a fork without the person beats
getting more done. Everything below the launch is governed by
[reference/rules.md](reference/rules.md); read it before the first piece of work and again
whenever a hook note names it.

The away script is `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/away.py"`, called `away.py` below;
every call carries `--session ${CLAUDE_SESSION_ID} --data-root "${CLAUDE_PLUGIN_DATA}"`, the data
root always passed as a literal argument in double quotes, so the script writes where the hooks
read. Pointer: when checking which variables a Bash command gets, fetch
<https://code.claude.com/docs/en/plugins-reference#where-each-variable-resolves>. Its `--help`
lists the commands.

## Launch, while the person is still here

Do these in order. No work in scope starts until `start` has succeeded, because a session with no away
state has silent hooks: prompts would wait all night and no report would exist.

1. **Read the absence from the words and the clock.** Run `date` for the local time and weekday.
   - A time or date in the words ("until 7am", "back at 14:00") is `--kind until --until <ISO local
     time>`.
   - A trip or a whole-day absence with no return time ("driving all day", "out until tomorrow") is
     `--kind trip`; with a return time it is `until`.
   - "Fresh session" in the words: see step 6 before running anything else.
   - No such words: `--kind bed`. The script decides the rest from the settings: inside the night
     window the report is due at the next report-by time; outside it the absence lasts until a
     message reads as the person being back. Relay the `report_by=` value it prints rather than
     computing your own.
   - A short break with no return time ("grabbing lunch", "back soon"): `--kind break`, which the
     script treats as `bed`.
   - Words that name an absence you cannot place on the clock ("for a while", "later"): ask now,
     one question with the choices, before `start`. This is the last question the person gets
     until they are back.
2. **Write the task file.** A checklist, one `- [ ] item` per piece of work in scope, taken from
   the approved plan, agent-ready items or the task in the conversation (rules.md "What counts as a
   plan"). Put it at `<launch checkout>/.work/away/tasks-<session id first 8>.md` when
   `git check-ignore` confirms that path is ignored; otherwise run `start` first and put it beside
   the report path it prints, then run `start` again with `--task-file` (a second `start`
   reconciles with the first). The hooks are live after the first `start`, so if that write is
   refused, say so in step 4: the run has no task file, and launching from a checkout whose
   `.work/` is ignored avoids it.
3. **Start.** Run, with the kind from step 1:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/away.py" start --session ${CLAUDE_SESSION_ID} --data-root "${CLAUDE_PLUGIN_DATA}" --kind <kind> [--until <ISO>] [--scope "<scope words>"] --task-file <task file> --setting 'away_night_start=${user_config.away_night_start}' --setting 'away_report_by_workday=${user_config.away_report_by_workday}' --setting 'away_report_by_day_off=${user_config.away_report_by_day_off}' --setting 'away_days_off=${user_config.away_days_off}' --setting 'away_watched_folders=${user_config.away_watched_folders}'
   ```

   Keep the settings in single quotes; the script treats an unexpanded `${user_config.…}` token as
   unset. Before running it, check each filled-in value: one that holds a single quote is an
   invalid setting, so stop the launch and name the option instead of running the command.
   Pointer: when checking how plugin options are substituted, fetch
   <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

   A non-zero exit stops the launch: tell the person it failed, quote the error, and say the
   session is not armed. Do not start the work. After every `start` that exits 0, run
   `away.py status` in a separate call: any status other than `"active"` means the state did not
   persist where the hooks read it (a Bash sandbox can do this), which is the same failure.
4. **End the launch turn with one message to the person**, doing no work in scope this turn: the
   Stop hook blocks the turn's end while task items are open and brings the run straight back to
   work, so this message is the last thing they read before leaving. It holds: the report path; the report-by time, or "until you are
   back"; every `warning=` line `start` printed, each in full; the context zone word from the
   `mcp__context-usage__status` tool, with a warning when the tool reports the zone as heavy (when
   the tool is absent, one line says the zone check was skipped); and that the first turn's end may add one more warning,
   that the permission mode is not auto. Never hand off later because of the context level: the
   run continues in this session through compaction unless the person asked for a fresh session.
5. **Propose the goal line** in that same message, for the person to submit before leaving, filled
   in with the real task file path, session id and data root:

   ```text
   /goal every item in <task file> is done or marked parked, and `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/away.py" check --session ${CLAUDE_SESSION_ID} --data-root "${CLAUDE_PLUGIN_DATA}"` exits 0
   ```

   Without it the Stop hook holds the same condition. The person typing this line, or a last
   instruction before leaving, is part of the launch and never reads as being back.
6. **Fresh session.** When the words ask for a fresh session, launch it and arm it from here while
   the person is present; `claude --bg` picks the new session's id, so `start` runs after the
   launch:
   1. Settle the absence (step 1, asking now if needed) and write the task file (step 2), named
      for this session's id. It needs the ignored `.work/` path, since `start` cannot run first;
      without one, offer to arm this session instead. Above the checklist, write a header line:
      this session runs in away mode; read `<rules>` before the first item, `<rules>` being the
      absolute path `${CLAUDE_PLUGIN_ROOT}/skills/step-away/reference/rules.md` resolves to. No
      hook gives the background session the rules or the report path, so this line does.
   2. Invoke `/session-flow:continue-in-background` through the Skill tool with the scope words
      and `done when every item in <task file> is done or marked parked`, a done condition stated
      in the invocation, which its gate's case 1 arms as the goal with no draft or confirmation.
      It hands back the background session's full `sessionId`.
   3. Run step 3's `start` at once with `--session <that sessionId>` in place of
      `${CLAUDE_SESSION_ID}`, then `status` for that id, failures handled as step 3 says. Append
      the report path `start` prints to the task file's header line.
   4. End with step 4's message, naming the background session and `claude attach <short id>`,
      and saying that what it did between its launch and `start` is outside the report.
      Skip step 5 and step 7 here; the background session does the work.

   No `sessionId` back (no launch, or no listing) → the background session is not armed: say so
   and offer to arm this session instead. Pointer: probe 4 in
   [continue-in-background's goal-probe.md](../continue-in-background/reference/goal-probe.md).
7. **Work**, from the turn after the launch message (the Stop hook's note or the person's `/goal`
   line starts it): read [reference/rules.md](reference/rules.md), then work the task file.

## Return

When a message reads as the person being back, run `away.py end`, show the report once leading
with Needs you, then run `away.py deliver`. Who counts as the person is in rules.md "Coming back".
`deliver` removes the absence's state and prints `report=<path>`, where the report stays: a report
kept beside the state moves to the plugin data's `away-reports/` folder, so give the person that
path when it differs from the one shown.

A parked Needs-you item runs only once the person accepts it, by naming it or through
`/session-flow:go-with-recommendations`; until then, answer the person and wait, ending each
answer with the open Needs-you items and their `Recommendation:` lines, so that skill finds them in
your latest message.

## Next

/session-flow:go-with-recommendations on return, to accept the parked recommendations once the
evidence is checked.

## Gotchas

- We keep the away hooks (PermissionRequest, Elicitation, Stop, UserPromptSubmit) in the
  plugin's `hooks/hooks.json`, not in this skill's frontmatter, and each does nothing unless this
  session's absence is active. Pointers: when checking what skill hooks are limited to, fetch
  <https://code.claude.com/docs/en/hooks#limits-on-skill-hooks>; for which hooks get the plugin
  data directory, <https://code.claude.com/docs/en/plugins-reference#where-each-variable-resolves>;
  the live run behind the choice is in this skill's pull request, melodic-software/claude-code-plugins#17337.
- Warn the person at launch that a sandboxed command's network prompt is not ours to refuse.
  Pointer: when checking which prompts reach the hook, fetch
  <https://code.claude.com/docs/en/hooks#permissionrequest>.
- Before launching an absence in a bypass-permission mode, check how that mode treats a
  PermissionRequest hook: fetch
  <https://code.claude.com/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode>.
- Keep the machine awake for the whole absence.
- With the Bash sandbox on, run `start`, `end` and `deliver` outside it while the person is here;
  during the absence the Stop hook keeps the report's script-owned blocks current.
  Pointer: when checking where sandboxed commands may write, fetch
  <https://code.claude.com/docs/en/sandboxing#filesystem-isolation>.
- A second `/session-flow:step-away` during an active absence reconciles with it and keeps its
  report; one after the absence ended starts a new absence with a new report.
