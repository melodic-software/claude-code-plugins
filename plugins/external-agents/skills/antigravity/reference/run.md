# Run and review

## Run

```bash
external-agents run antigravity --use <task|investigate> --prompt-file <file> [--mode read-only|write] [--add-dir <absolute dir>]... [--unsandboxed auto] [--model <model>] [--effort <level>] [--resume <thread-id>|--last]
```

- **Decide the write fence before the run.** List every directory outside the worktree the task
  will write, and pass each one with its own `--add-dir <absolute path>`; pass none when the
  worktree is enough. Pass exactly those, never a parent folder to be safe. Name the same
  directories in the prompt, and tell agy to write nowhere else.
- **Opt out of the sandbox only for a command that needs it.** In the same decision, ask whether
  the task must run a command outside agy's terminal sandbox: network access, or a system service.
  Only then pass `--unsandboxed auto`, and say in the prompt which command needs it and why. A
  task that only edits files and runs local builds or tests stays on the default fence.
- `--add-dir` and `--unsandboxed` take a write run: on a read-only run, a review, a relative path
  or a directory that does not exist, the command refuses with exit `2` and starts nothing.
  `external-agents status <job>` prints the run's `fence:` (`sandbox` or `unsandboxed auto`) and
  `add_dirs:`.
- **Pick the use from the request.** `task` with `--mode write` when agy should change files;
  `investigate` when it should only read and answer. The use's configured mode
  (`antigravity.uses.<use>.mode`, bundled values in the plugin's `defaults.json`) is both the
  default and the ceiling. Every use is read-only by default: writes need
  `antigravity.uses.task.mode: write` from the user. `--mode write` never lifts a read-only
  ceiling; under one, the run is read-only and prints the notice naming that key. Pass
  `--mode read-only` to run a task without writes.
- **Model and effort.** By default pass neither: `antigravity.model` and `antigravity.effort` from config
  apply when set, and agy's own default applies when not. Pass `--model` or `--effort` for one
  run when the user names one, or when `/multi-agent:route vendors <task>` recommends one for a
  heavy whole-task delegation. Name the override and its basis in the reply.
- **Resume** continues an agy conversation this plugin started. `--resume <thread-id>` takes a
  `thread_id` from `external-agents status <job>`; a thread that is not in this repository's job
  files is refused. `--last` resumes this plugin's newest job with a thread in this repository. A
  resumed run gets the current use's mode again.
- **Timeout.** A run that passes `antigravity.timeout_seconds` is stopped and recorded
  `timed-out`.
- agy works in the current directory. Run from the repository or worktree agy should work in.

### How each mode holds

- **read-only** runs agy's default mode with a per-run settings file; agy refuses every shell
  command and file write it would have to ask about, and the command records each refusal from
  agy's `denied_actions` field. The prompt gets a preface saying so, so name the files to read.
- **write** (fence `sandbox`, the default) runs `--mode accept-edits` with a per-run settings file
  that turns on agy's terminal sandbox, lets sandboxed commands proceed, and turns off access
  beyond the workspace and the `--add-dir` directories. A command that asks to leave the sandbox
  is refused, and the run is recorded `blocked-by-mode`. What each setting does is agy's to state:
  [Execution modes § Auto-approve edits with accept-edits mode](https://antigravity.google/docs/cli/modes#auto-approve-edits-with-accept-edits-mode) and
  [Terminal sandbox § CLI configuration](https://antigravity.google/docs/sandbox#cli-configuration).
- **write with `--unsandboxed auto`** (fence `unsandboxed auto`) runs `--mode auto`, whose
  out-of-sandbox commands agy decides on itself
  ([Terminal sandbox § CLI permissions integration](https://antigravity.google/docs/sandbox#cli-permissions-integration)).
  Its limits are in the hub's gotchas.

### First stdout line

`antigravity: <status>` with a parenthesized reason and details when there are any, such as the
refused actions and the mode that refused them. Statuses: `ok`, `failed`, `blocked-by-mode`,
`timed-out`, `cancelled`. A run stopped before agy started prints `antigravity: failed (...)`,
`antigravity: skipped (...)`, `antigravity: unavailable: ...` or `antigravity: refused: ...`.
agy's final message follows the line whenever agy produced one.

stderr carries `job: <id>` and any `notice:` lines (mode ceiling, config problems, agy's own
warnings, a foreign `CLAUDE_PLUGIN_DATA`). Relay every notice.

## Review

```bash
external-agents review antigravity --base <ref> [--brief-file <file>] [--model <model>] [--effort <level>]
```

- Always read-only, whatever any config says. `<ref>` must be a commit that shares history with
  `HEAD`; the review covers the merge base with it up to `HEAD`.
- The command writes the diff into the job's own folder, gives agy read access to that folder
  only, and names the file in the prompt; agy never runs `git`.
- `--brief-file` adds review instructions (a focus, a threat model). Write it like a prompt file:
  paths and questions, no pasted contents.
- First line: `antigravity: ran (...)`, `antigravity: failed (...)` or
  `antigravity: skipped (...)`; this is the same line council reads. Findings follow `ran` only.
  Exit `0` for `ran`, else `1`, `2` or `4`.
- A `notice:` about `.agents/` means the branch carries agy workspace configuration (hooks) that
  loads into the review: relay it before the findings.
