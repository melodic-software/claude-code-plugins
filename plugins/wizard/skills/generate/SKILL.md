---
description: "Generate an interactive bash wizard script that walks a human through the steps only they can perform. The agent authors the script and never runs it; the human runs it in their own terminal. Use when: 'provisioning infrastructure', 'provisioning credentials', 'set up CI secrets', 'walk me through the dashboard', 'guided setup script', 'one-off migration', 'cutover', or a manual dashboard, credential, or third-party-console step is what blocks progress. Don't invoke this for steps the agent can perform itself."
metadata:
  workflow-stage: anytime
  summary: Author a hardened interactive bash wizard for human-only setup, credential, and cutover steps
---

# Generate a wizard

A **wizard** is a bash script that walks a human, step by step, through a manual
procedure that's tedious to do by hand and tedious to re-explain every time. It
opens each URL, says exactly what to click and copy, captures the values, writes
them where they belong (`.env`, CI secrets), confirms at every stage, and shows
how many stages are left.

The UX and the security hardening are already solved by [template.sh](template.sh) —
stage-by-stage progress, fail-closed TTY-only prompts, https-only URL opening
(cross-platform incl. WSL and Git Bash), hidden secret entry, quoted `0600`
`.env` upserts with a gitignore check, repo-confirmed `gh secret`/`gh variable`
writes over stdin, and a closing names-only summary. **Your job is only to scope
the procedure and author its stages.** The library above the `STAGES` marker is
identical in every wizard; that consistency is the point — never hand-edit it.

A wizard is ephemeral by default — built for one run, saved to a scratch or
`scripts/` path, deleted when the job's done. Commit it only when the user wants
a repeatable setup path that should live in the repo.

The generated script requires bash; on Windows the supported path is Git Bash or
WSL. `gh` (authenticated) is needed only by stages that write CI secrets or
variables — when it's absent those stages warn and land in the closing summary
instead of failing the run.

## Process

### 1. Scope the procedure

Work out every manual step the human must take and every value that gets
captured along the way. Read the repo first — don't ask cold:

- For setup: read `.env.example`, `README`, `docker-compose*`, framework config,
  and `.github/workflows/*` fully (every `secrets.*` / `vars.*` reference is a
  value the wizard must produce). From a **live** `.env`, take **key names
  only** — e.g. `grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' .env` — never values.
- For a migration or transition: the current state, the target state, and the
  irreversible actions between them.

Be honest about what reaches the model if the user asks: values the wizard
captures at runtime never reach the model — the human runs the script and it
writes captures straight to `.env` or `gh`. Authoring-time reads are names-only
by the rule above. A value the user pastes into the chat, though, is in context
like any other pasted text.

Then show the user the ordered list of stages and the values each produces, and
confirm — they may add, drop, or reorder.

**Done when:** every stage is named in order, and for each captured value you
know (a) where the human gets it, (b) where it's written (`.env`, a CI secret,
both, or nowhere — some stages are pure actions), and (c) whether it's secret
(hidden entry) or public.

### 2. Map each stage's journey

For each stage, write the precise path a human follows: which URL to open, what
to do there, where a value is shown, which variable it fills — e.g. "Dashboard →
Developers → API keys → Reveal test key → copy". Where you don't actually know
the current UI or the exact command, say so and ask the user or check the docs —
never invent steps that may not exist.

**Done when:** every stage traces to concrete instructions a stranger could follow.

### 3. Author the wizard

Copy [template.sh](template.sh) to the target path. Replace the example stage
with one `stage` per step, in dependency order. Use the library helpers —
`stage`, `say`/`step`/`note`/`warn`, `open_url`, `ask`/`ask_secret`,
`write_env`, `set_secret`/`set_var`, `pause`/`confirm` — and set `TOTAL_STAGES`
to the number of stages you wrote.

Hold the bar the template sets: open the URL (https only) before asking for its
value, use `ask_secret` for anything secret, `write_env` every persisted value,
`set_secret` only the values CI actually needs, and `confirm` before any
irreversible action. Each `stage` clears the screen so only the current step is
visible — keep a stage to one focused task so nothing the human needs scrolls
away. Don't touch the library above the marker.

### 4. Verify and hand off

1. `bash -n <script>`; run `shellcheck` if available. Fix what they find.
2. Trace it statically — never run it end-to-end yourself: it opens browsers and
   blocks on human input, and the agent-never-executes line is the security
   model. Dispatch a fresh-context subagent to do the trace: hand it the script
   and the step-1 value list (artifact only, not your reasoning), and have it
   verify that every value from step 1 is captured and lands where step 1 said,
   <!-- portability-ok: matching set_secret names to CI secrets.* references applies only when the consumer's declared CI-secret destination is GitHub Actions -->
   that every `set_secret`/`set_var` name exactly matches a `secrets.*`/`vars.*`
   reference in CI, and that nothing above the `STAGES` marker was edited.
3. **Stop the line — human approval gate.** Print the full `STAGES` block
   (everything below the marker) to the user and get their explicit approval.
   Do NOT `chmod +x` the script, and do NOT tell the user to run it, until they
   have read the stages and approved them. This is a hard ordering, not a
   suggestion: the human is about to feed real credentials to this script, so
   the human reads it first.
4. Only after approval: `chmod +x <script>`, then tell the user how to run it.
   If it's a repeatable setup path, offer to commit it and link it from the
   README so the next person runs the script instead of asking an AI.

## Gotchas

- **No back button.** A wrong answer means Ctrl-C and re-run — cheap by design:
  values already in `.env` are offered back as defaults, so the human presses
  Enter through the stages they got right.
- **TTY required.** The script refuses to start without `/dev/tty`, so it will
  not run piped, in CI, or driven by pasted input. That is deliberate.
- **Arrow keys** work in `ask` prompts (readline) but not in `ask_secret`
  (hidden entry has no line editing) — backspace works in both.
- **`gh` absence is not an error.** CI-secret stages degrade to a warning plus a
  closing-summary entry telling the human what to set by hand.
