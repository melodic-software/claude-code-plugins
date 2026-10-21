# `/goal` in a background launch: probe record

Detail behind the completion condition gate in [SKILL.md](../SKILL.md). The gate rests on this
probe, not on a docs page; the section to recheck for where a goal runs is
<https://code.claude.com/docs/en/goal#run-non-interactively>.

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| Pass the condition as the launched session's first prompt, `/goal <payload>`, read from a prompt file into `claude --bg --permission-mode auto "$(cat <file>)"` | The two probes below, run 2026-10-20 on Claude Code 2.1.304, Linux (WSL2) | 2026-10-20 | A release note changes how a background session's first prompt runs a slash command, the section above starts or stops naming background sessions, or a launch's transcript has no `Goal set:` line |
| When the CLI refuses the `--cloud` launch for lack of a terminal, take the local `--bg` delivery instead | Probe 3 below, run 2026-10-20 on Claude Code 2.1.306, Linux (WSL2) | 2026-10-20 | A release lets `--cloud` start without a terminal, or <https://code.claude.com/docs/en/claude-code-on-the-web#start-a-cloud-session-from-your-terminal> changes how the terminal launch starts |

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

Sessions 1 and 2 were stopped and removed with `claude stop` and `claude rm` afterwards; probe 3
left no cloud session, branch or pull request. Whether a `--cloud` session arms a goal from its
first prompt is still unprobed: it needs one launch typed in a terminal from a trusted checkout.
