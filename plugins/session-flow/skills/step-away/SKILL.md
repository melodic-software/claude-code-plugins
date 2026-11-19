---
description: "Run this session alone while the person is away (AFK): refuse prompts, park their decisions, and keep a return report."
argument-hint: "[until <time>|<trip>|fresh session] [scope ...]"
user-invocable: true
disable-model-invocation: true
hooks:
  # Exec form. `command` is `node` (a real executable). exec-bash.mjs finds
  # Git Bash and never System32\bash.exe, then runs run-away-hook.sh, which
  # finds Python and runs away.py hook <event>. Bare `bash` or `python3` as
  # `command` is the launch that fails open on Windows.
  # A skill-frontmatter hook substitutes only ${CLAUDE_PLUGIN_ROOT} (our
  # probe, PR #1014). These two hooks stay with the main session; the
  # PermissionRequest and Elicitation hooks live in hooks/hooks.json because
  # frontmatter hooks do not reach subagents (probe Q-F).
  # Pointer: when checking how exec form spawns `command` with `args`, fetch
  # https://code.claude.com/docs/en/hooks#exec-form-and-shell-form and
  # https://code.claude.com/docs/en/hooks#command-hook-fields live.
  Stop:
    - hooks:
        - type: command
          command: node
          args: ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "${CLAUDE_PLUGIN_ROOT}/hooks/run-away-hook.sh", "Stop"]
          timeout: 60
  UserPromptSubmit:
    - hooks:
        - type: command
          command: node
          args: ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "${CLAUDE_PLUGIN_ROOT}/hooks/run-away-hook.sh", "UserPromptSubmit"]
          timeout: 30
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
every call carries `--session ${CLAUDE_SESSION_ID} --data-root ${CLAUDE_PLUGIN_DATA}`, the data
root passed as a literal argument in double quotes, since the Bash tool's environment does not
carry it and the hooks read state from there. Its `--help` lists the commands.

## Launch, while the person is still here

Do these in order. Nothing else runs until `start` has succeeded, because a session with no away
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
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/away.py" start --session ${CLAUDE_SESSION_ID} --data-root "${CLAUDE_PLUGIN_DATA}" --kind <kind> [--until <ISO>] [--scope "<scope words>"] --task-file <task file> --setting "away_night_start=${user_config.away_night_start}" --setting "away_report_by_workday=${user_config.away_report_by_workday}" --setting "away_report_by_day_off=${user_config.away_report_by_day_off}" --setting "away_days_off=${user_config.away_days_off}" --setting "away_watched_folders=${user_config.away_watched_folders}"
   ```

   A non-zero exit stops the launch: tell the person it failed, quote the error, and say the
   session is not armed. Do not start the work. Then run `away.py status` in a separate call: a
   `"status": "none"` there means the state did not persist where the hooks read it (a Bash
   sandbox can do this), which is the same failure.
4. **Tell the person, in one message:** the report path; the report-by time, or "until you are
   back"; every `warning=` line `start` printed, each in full; the context zone word from the
   `mcp__context-usage__status` tool, with a warning when that plugin's reader contract counts it
   heavy (when the tool is absent, one line says the zone check was skipped); and that the first turn's end may add one more warning,
   that the permission mode is not auto. Never hand off later because of the context level: the
   run continues in this session through compaction unless the person asked for a fresh session.
5. **Propose the goal line** for the person to submit before leaving, filled in:

   ```text
   /goal every item in <task file> is done or marked parked, and `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/away.py" check --session ${CLAUDE_SESSION_ID} --data-root "${CLAUDE_PLUGIN_DATA}"` exits 0
   ```

   Without it the Stop hook holds the same condition. The person typing this line, or a last
   instruction before leaving, is part of the launch and never reads as being back.
6. **Fresh session.** The away state and hooks belong to the session that ran `start`, and a
   background session launched from here starts on its `/goal` line, so this skill cannot arm it.
   When the words ask for a fresh session, say so while the person is here and let them choose:
   stay in this session armed (recommended: prompts are refused and the report is kept), or hand
   off unarmed by invoking `/session-flow:continue-in-background` through the Skill tool with
   their own words. Run no `start` for the hand-off.
7. **Work.** Read [reference/rules.md](reference/rules.md), then work the task file.

## Return

When a message reads as the person being back, run `away.py end`, show the report once leading
with Needs you, then run `away.py deliver`. Who counts as the person is in rules.md "Coming back".

## Next

/session-flow:go-with-recommendations on return, to accept the parked recommendations once the
evidence is checked.

## Gotchas

- The Stop and UserPromptSubmit hooks stay registered for the rest of the session, and the
  plugin's PermissionRequest and Elicitation hooks run in every session; all of them do nothing
  unless this session's absence is active.
- A sandboxed command's network prompt never reaches a hook, so it cannot be refused and waits for
  the person. Pointer:
  <https://code.claude.com/docs/en/hooks#permissionrequest>.
- While the absence is active the PermissionRequest hook answers every prompt, which changes what
  the bypass-permission modes do for the rest of it. Pointer:
  <https://code.claude.com/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode>.
- Keep the machine awake: a sleeping machine stops the run, and the resume after a usage limit
  can wait for a keypress.
- A second `/session-flow:step-away` during an active absence reconciles with it and keeps its
  report; one after the absence ended starts a new absence with a new report.
