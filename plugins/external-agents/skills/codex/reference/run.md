# Run and review

## Run

```bash
external-agents run codex --use <task|investigate> --prompt-file <file> [--mode read-only|write] [--model <model>] [--resume <thread-id>|--last]
```

- **Pick the use from the request.** `task` when Codex should change files; `investigate` when it
  should only read and answer. The use's configured mode (`codex.uses.<use>.mode`, bundled values
  in the plugin's `defaults.json`) is both the default and the ceiling. Pass `--mode read-only` to
  run a task without writes; `--mode write` never lifts a read-only ceiling.
- **Model and effort.** Pass `--model` only when the user names one for this run. Otherwise pass
  nothing: `codex.model` and `codex.effort` from config apply when set, and Codex's own
  configuration and default apply when not. Choosing one: [routing.md](routing.md).
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
external-agents review codex --base <ref> [--brief-file <file>] [--model <model>]
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
