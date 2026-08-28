# wizard

A Claude Code plugin that generates **interactive bash wizards**, scripts that
walk a human, step by step, through the manual procedures an agent cannot
perform: provisioning infrastructure or credentials, setting CI secrets,
clicking through an unfamiliar third-party dashboard, or sequencing a one-off
migration or cutover. The wizard opens each URL, says exactly what to click and
copy, captures the values, writes them where they belong (`.env`, CI secrets),
and confirms at every stage.

| Skill | What it does |
|---|---|
| `/wizard:generate` | Scope the manual procedure from the repo, author its stages onto the fixed hardened template, verify statically, and hand off to the human after explicit approval |

The skill is model-invoked: when the agent hits a step only a human can take,
a key it can't mint, a dashboard it can't click, it can reach for this instead
of dumping numbered instructions into the chat. It is fenced the other way too:
it never fires for steps the agent can perform itself.

## Security posture

- **The agent authors the script; it never runs it.** The human runs the wizard
  in their own terminal. The script itself refuses to start without a
  controlling TTY (`/dev/tty`), so its confirmation gates cannot be satisfied by
  piped or pasted input.
- **Human approval gate.** The skill's verify step is stop-the-line: the full
  `STAGES` block is printed to the user and explicitly approved BEFORE the
  script is made executable or offered for running.
- **Captured values never reach the model.** Runtime capture happens in the
  human's terminal (hidden entry for secrets) and writes straight to `.env` or
  `gh`; the model is not connected to the running script. At authoring time the
  skill reads key **names** only from a live `.env`, never values. The honest
  caveat: a value the user pastes into the chat is in context like any other
  pasted text.
- **Hardened template.** The fixed library above the `STAGES` marker is never hand-edited and is
  identical in every wizard. It enforces:
  - https-only URL opening, with the full URL printed before dispatch.
  - Fail-closed prompts: a closed terminal aborts rather than falling through.
  - Key-name validation.
  - Single-quoted, escaped `.env` values, with `chmod 600` after every write, an is-it-gitignored
    check, and trap-cleaned atomic temp-file rewrites.
  - GitHub writes that resolve and echo the target repo once, require explicit confirmation before
    the first write, pass `--repo` on every call, pipe values over stdin rather than argv, refuse
    empty values, and surface `gh` errors into the closing summary.
  - A names-only closing summary.

## Prerequisites

- **bash**, to run the generated script. On Windows the supported path is Git
  Bash or WSL. (Generating a wizard needs nothing beyond the agent itself.)
- **`gh` (GitHub CLI), optional**. Only for stages that write GitHub Actions
  secrets or variables. When `gh` is missing or unauthenticated those stages
  warn visibly and land in the closing to-do summary instead of failing the
  run. Wizards whose values live only in `.env` never touch `gh`.

## Ephemeral by default

A wizard is built for one run: save it to a scratch or `scripts/` path, run it,
delete it. Commit it only when it is a repeatable setup path the next person on
the repo will also need. Then link it from the README so they run the script
instead of re-asking an agent.

## Setup skill assessment

This plugin ships no `setup` skill, per the philosophy's criteria: it has (a) no
consumer-project configuration surface, (b) no external prerequisite for its own
operation, and (c) no `userConfig` at all. `bash` and `gh` are prerequisites of
the *generated artifact's run*, declared above and at the point of use in the
generated script itself, which degrades visibly when `gh` is absent. Setup
would be blanket ceremony with nothing to check or apply.
