# `/goal` in a background launch: probe record

Detail behind the completion condition gate in [SKILL.md](../SKILL.md). The gate rests on this
probe, not on a docs page; the section to recheck for where a goal runs is
<https://code.claude.com/docs/en/goal#run-non-interactively>.

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| Pass the condition as the launched session's first prompt, `/goal <payload>`, read from a prompt file into `claude --bg --permission-mode auto "$(cat <file>)"` | The two probes below, run 2026-10-20 on Claude Code 2.1.304, Linux (WSL2) | 2026-10-20 | A release note changes how a background session's first prompt runs a slash command, the section above starts or stops naming background sessions, or a launch's transcript has no `Goal set:` line |
| When the CLI refuses the `--cloud` launch for lack of a terminal, take the local `--bg` delivery instead | Probe 3 below, run 2026-10-20 on Claude Code 2.1.306, Linux (WSL2) | 2026-10-20 | A release lets `--cloud` start without a terminal, or <https://code.claude.com/docs/en/claude-code-on-the-web#start-a-cloud-session-from-your-terminal> changes how the terminal launch starts |
| Take the docs' account of a goal staying active in a cloud session as a correlate only; first-prompt arming from a `--cloud` launch stays unprobed | <https://code.claude.com/docs/en/goal#errors-you-have-to-fix-clear-the-goal> |  |  |
| step-away arms a fresh background session after launch, with `away.py start --session <full sessionId>` from the launching session, the id read from `claude agents --json --all` | Probe 4 below, run 2026-11-19 on Claude Code 2.1.328, Linux (WSL2) | 2026-11-19 | A release lets `--bg` take `--session-id`, changes the `claude agents --json` fields, or a launch's away state is never rewritten by its Stop hook |

## What the probes observed

Both ran from a trusted project directory. From the home directory the launch failed with
"Workspace not trusted", so the skill's launch from the project root is the tested route.

1. **One line.** First prompt `/goal the file <tmp>/goal-probe.txt exists: create it with the
   Write tool containing the word probe, then show its contents with the Read tool`. The session
   transcript recorded the `/goal` command, its `Goal set: …` output, a notice that a
   session-scoped Stop hook was active with that condition, the Write and Read calls, and then a
   goal status entry marked met.
2. **The payload's shape.** A prompt file holding `/goal <condition>` on line 1 and
   `Read @<tmp>/goal-probe2-brief.md, then do what it says.` on line 2. `Goal set:` held both
   lines as one condition, the agent followed the brief the `Read @` line named, and the goal
   status entry was marked met. This is the shape the full path sends: a condition ending in the
   resume region's `Read @` directive.
3. **`--cloud` from a Bash tool.** First prompt `/goal <a reply holding a fixed token spelled
   backwards; no tool, file edit, commit, branch, push or pull request>`, launched with
   `claude --cloud "$(cat <file>)"` from a clean checkout of a sandbox repository. With no
   terminal the CLI refused at once: `Error: --cloud requires an interactive terminal.` Under a
   pseudo-terminal (`script -qfc`) from a checkout that had not been trusted, it stopped at the
   workspace-trust dialog. Neither attempt created a cloud session, so arming was never reached.
4. **Arming a background session after its launch.** `claude --bg --name <name>
   --permission-mode auto --setting-sources local --settings '{"worktree":{"bgIsolation":"none"}}'
   --plugin-dir <checkout>/plugins/session-flow "$(cat <payload file>)"`, from a folder under the
   checkout's ignored `.work/`, the payload `/goal every item in <task file> is ticked done or
   marked parked` and a line asking for the two task items in order. The launch printed the
   8-character short id; `claude agents --json --all` gave the entry with that `id` and its full
   `sessionId`. `--session-id` is no route: `--bg` ignores it with a warning (probe p6 on
   melodic-software/claude-code-plugins#17386). Then, as separate tool calls the way a skill
   makes them, `away.py start --session <full sessionId>` ran with `--data-root` set to the
   `--plugin-dir` load's data folder, `<plugin data>/session-flow-inline`. Timeline, from the
   session's transcript and the state file's times:
   - launch returned at 0 s; `Goal set:` and the first prompt at 1.5 s, with no away state, so
     that prompt's UserPromptSubmit added no away note;
   - `start` wrote the state at 7.8 s, while the session was still in its first turn;
   - the away Stop hook rewrote `state.json` at 13.7 s, so the first Stop read the state. Both
     items were already ticked, so it did not block.

   The window is the time from launch to `start`: the away hook refuses no permission prompt
   raised then (none was raised here), and the first turn runs without the away note. The report
   scans from `start`, so actions before it are not listed. A first turn that ends inside the window goes unheld by the away hook, but the goal
   names the task file, so the session keeps working and its next Stop reads the state. The Stop
   hook did not record the transcript path, so `refresh` finds the transcript under the config
   folder's `projects/` by session id; the probe's `refresh` listed it. Untested: a launch with
   worktree isolation on, where the task file and report sit outside the session's worktree.

Sessions 1 and 2 were stopped and removed with `claude stop` and `claude rm` afterwards; probe 3
left no cloud session, branch or pull request. Session 4 was stopped and removed the same way,
and `away.py end` and `deliver` cleared its state. Whether a `--cloud` session arms a goal from its
first prompt is still unprobed: it needs one launch typed in a terminal from a trusted checkout.
