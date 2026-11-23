# Run and review

## Run

```bash
external-agents run codex --use <task|investigate> --prompt-file <file> [--mode read-only|write] [--add-dir <absolute dir>]... [--model <model>] [--effort <level>] [--resume <thread-id>|--last]
```

- **Decide the extra directories before the run.** A write run is fenced to the worktree by
  Codex's `workspace-write` sandbox. List every directory outside the worktree the task will
  write, and pass each one with its own `--add-dir <absolute path>`; pass none when the worktree is
  enough. Pass exactly those, never a parent folder to be safe. Name the same directories in the
  prompt, and tell Codex to write nowhere else.
- `--add-dir` takes a new write run: on a read-only run, a review, a resumed thread, a relative
  path or a directory that does not exist, the command refuses with exit `2` and starts nothing.
  `external-agents status <job>` prints the run's `fence:` and `add_dirs:`.
- **Pick the use from the request.** `task` when Codex should change files; `investigate` when it
  should only read and answer. The use's configured mode (`codex.uses.<use>.mode`, bundled values
  in the plugin's `defaults.json`) is both the default and the ceiling. Pass `--mode read-only` to
  run a task without writes; `--mode write` never lifts a read-only ceiling.
- **Model and effort.** By default pass neither: `codex.model` and `codex.effort` from config
  apply when set, and Codex's own default applies when not. Pass `--model` or `--effort` for one
  run when the user names one, or when `/multi-agent:route vendors <task>` recommends one for a
  heavy whole-task delegation. Name the override and its basis in the reply.
- **Resume** continues a Codex thread this plugin started. `--resume <thread-id>` takes a
  `thread_id` from `external-agents status <job>`; a thread that is not in this repository's job
  files is refused. `--last` resumes this plugin's newest job with a thread in this repository,
  not Codex's own most recent session. A resumed run gets the current use's mode again.
- **Timeout.** A run that passes `codex.timeout_seconds` is stopped and recorded `timed-out`.
- Codex starts in the current directory. Run from the repository or worktree Codex should work in.

### First stdout line

`codex: <status>` with a parenthesized reason and details when there are any: blocked commands and
the mode that blocked them, failed commands, MCP calls with tool names. Statuses: `ok`, `failed`,
`blocked-by-mode`, `timed-out`, `cancelled`. A run stopped before Codex started prints
`codex: failed (...)`, `codex: skipped (...)`, `codex: unavailable: ...` or `codex: refused: ...`.
Codex's final message follows the line whenever Codex produced one.

stderr carries `job: <id>` and any `notice:` lines (mode ceiling, config problems, a foreign
`CLAUDE_PLUGIN_DATA`). Relay every notice.

## Review

```bash
external-agents review codex --base <ref> [--brief-file <file>] [--model <model>] [--effort <level>]
```

- Always read-only, whatever any config says. `<ref>` must be a commit that shares history with
  `HEAD`; the review covers the merge base with it up to `HEAD`.
- `--brief-file` adds review instructions (a focus, a threat model). Write it like a prompt file:
  paths and questions, no pasted contents. The command adds the merge base and the changed-file
  list itself.
- First line: `codex: ran (reviewed N changed files against <sha>; ...)`, `codex: failed (...)` or
  `codex: skipped (...)`; this is the same line council reads. Findings follow `ran` only. Exit `0`
  for `ran`, else `1`, `2` or `4`.
- A `notice:` about `.codex/` means the branch carries Codex configuration that runs outside the
  sandbox: relay it before the findings.
