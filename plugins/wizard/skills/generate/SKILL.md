---
description: "Write a bash script, an interactive wizard, to guide a person through setup work only they can carry out. The agent writes the script and never executes it; the person runs it in their own terminal. Use when: 'provisioning infrastructure', 'provisioning credentials', 'set up CI secrets', 'walk me through the dashboard', 'guided setup script', 'one-off migration', 'cutover', or progress is blocked on a manual dashboard, credential, or third-party-console step. Skip it for any step the agent can do on its own."
argument-hint: "<procedure to wizardize>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Author a hardened interactive bash wizard for human-only setup, credential, and cutover steps
---

# Generate a wizard

Some setup needs a person at a browser: signing in to a vendor console, creating a token, adding a
DNS record, approving a cutover. Chat instructions for that get lost and have to be written again
for the next person. A wizard keeps those instructions in a bash script instead. The person
runs it, and it leads them through the work one screen at a time.

## Running example

This page uses one fictional case throughout. A project is adding a transactional mail provider and
needs three stages:

- **Sending domain.** The person registers the domain in the provider's console; the wizard keeps
  `MAIL_FROM_DOMAIN` (public) in `.env`.
- **DNS records.** The person adds the records the console lists at their registrar. Nothing is
  captured; the stage is an action only.
- **API token.** The person creates a token with send scope. The wizard keeps `MAIL_API_TOKEN`
  (secret) in `.env`, and also as a CI secret, because the deploy workflow reads
  `secrets.MAIL_API_TOKEN`.

At stage 3 the person sees a `Stage 3/3` header, the console's API page opens in their browser, a
line tells them which button creates the token, they paste it into a prompt that does not echo, and
the script confirms it was saved to `.env` and to the repository's CI secrets.

## What you write, and what is fixed

[template.sh](template.sh) has two parts. Above its `STAGES` marker is a library that is the same in
every wizard: never edit it, because a wizard can be trusted only while that part does not vary.
Below the marker is an example stage that you replace. Your work is the stage plan and the stage
code, nothing else. The library already covers:

| Concern | How the library handles it |
|---|---|
| Prompts | Read only from `/dev/tty` and fail closed, so a pipe, a CI job or a pasted block cannot answer them |
| Opening pages | Accepts `https://` URLs only and prints each one before opening it, on macOS, Linux, WSL and Git Bash |
| Secret input | `ask_secret` hides what is typed |
| `.env` writes | Values quoted, file mode `0600`, rewritten atomically (through a symlinked `.env` too), with a warning when the file is not gitignored |
| CI writes | `gh secret` / `gh variable` with the value on stdin, after the person confirms the target repository |
| Progress and wrap-up | A stage counter, and a closing summary that lists names, never values |

Running a wizard needs bash; on Windows, use Git Bash or WSL. An authenticated `gh` matters only to
stages that write CI secrets or variables. Without it, those stages print a warning and appear in
the closing summary as manual work, and the rest of the run carries on.

## Phase 1: the stage plan

The plan is one table, a row per stage in run order. For the running example:

| Stage | Value | Secret | Saved to | How the person gets it |
|---|---|---|---|---|
| Sending domain | `MAIL_FROM_DOMAIN` | no | `.env` | Mail console: Domains, Add domain, enter the domain |
| DNS records | none | n/a | nowhere | Registrar: DNS settings, add each record the console listed |
| API token | `MAIL_API_TOKEN` | yes | `.env` and CI secret | Mail console: API, Create token, send scope, copy it |

Fill the table from the repository; the user answers only what the files cannot. Which file answers
which column:

| To learn | Look in |
|---|---|
| Values CI must receive | Each workflow under `.github/workflows/*`, read whole: a `secrets.*` or `vars.*` reference means a row whose Saved to includes CI |
| Values the app reads locally | `.env.example`, `docker-compose*`, the framework's config files |
| Manual steps already written down | `README` |
| Keys this machine already has | The live `.env`, key names only: `grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' .env`. Its values are never read |

A migration or cutover table gets two extra things: a first row stating the system as it stands and
a last row stating the state it must reach, and a column marking each row in between that cannot be
reversed (those rows get a `confirm` in Phase 2).

The last column is written for a newcomer: page address, menu, button, field. A cell you cannot fill
from knowledge you trust (a console redesigned since you last saw it, a CLI flag you are not sure
of) is marked `unverified`. Before the table goes to the user, resolve each such cell from the
vendor's documentation, or ask the user for it in the same message.

The table is the user's to change until they confirm it. Phase 1 ends at that confirmation, with
no empty or `unverified` cell left.

What the model sees, if the user asks, depends on the path a value takes:

| Path | Reaches the model? |
|---|---|
| The person types it into the running wizard, which writes `.env` or calls `gh` | No |
| The skill reads the live `.env` while planning | Key names only |
| The user pastes it into this chat | Yes, as any pasted text does |

## Phase 2: the stage code

Work in a copy of [template.sh](template.sh) at the chosen path. Delete its example stage and leave
every line above the `STAGES` marker exactly as it is. The confirmed table then decides the code,
cell by cell:

| Table content | Code it produces |
|---|---|
| Each row, in table order | One `stage` call; `TOTAL_STAGES` equals the row count |
| How the person gets it | `say`, `step`, `note` and `warn` lines, plus `open_url` (https only) for the page, placed before any prompt for a value from that page |
| Secret: no / yes | `ask` / `ask_secret` |
| Saved to `.env` | `write_env` |
| Saved to CI | `set_secret` for a secret, `set_var` for a public value; never for a value CI does not read |
| A step that cannot be undone | `confirm` (a yes-or-no question) ahead of it |
| Value: none | No prompt; `step` lines and a `pause`, which waits for the person |

`stage` clears the terminal and prints the counter, so a row that holds two tasks loses the first
task's instructions off the top of the screen. Split such a row in two. In the running example,
stage 2 is the no-prompt case; stage 3 calls `open_url` on the API page, `ask_secret
MAIL_API_TOKEN`, `write_env`, and `set_secret`, in that order.

## Phase 3: checks and approval

1. Run `bash -n <script>`, and `shellcheck` when it is installed. Fix whatever they report.
2. Never execute the wizard. It opens a browser and waits for a person, and the fact that the agent
   never runs it is what keeps captured values away from the model. Check it by reading instead,
   in a fresh-context subagent given the script and the Phase 1 table only (not your reasoning).
   The subagent confirms:
   - each value in the table is captured and saved to the destination the table names;
   <!-- portability-ok: matching set_secret names to CI secrets.* references applies only when the consumer's declared CI-secret destination is GitHub Actions -->
   - each `set_secret` / `set_var` name is spelled exactly as a `secrets.*` / `vars.*` reference
     in the CI workflows;
   - the library above the `STAGES` marker is unchanged.
3. **Stop the line. Human approval gate.** Show the user the whole `STAGES` block, everything below
   the marker, and wait for their explicit approval. Until it arrives, do NOT run `chmod +x` and do
   NOT give the user a command to run. The order is fixed, not advisory: the person is about to type
   real credentials into this script, so they read it before it can run.
4. After approval, run `chmod +x <script>` and tell the user how to start it.
5. Ask the user one question: will this setup recur for other contributors? Without a yes, the
   script is a one-time tool: it sits in a scratch directory or `scripts/`, never enters git, and
   is deleted after its run. With a yes, it becomes the repository's record of the setup, kept as
   code rather than rebuilt in each contributor's chat: commit it and add a link to it in the
   README.

## Next

`/wizard:unattended` when the remaining work is fully scriptable and a human is only the privilege or policy boundary.

## Gotchas

- **Corrections cost a restart and little else.** Stages only move forward. Each prompt whose key
  is already in `.env` shows `[Enter keeps current]`, so after Ctrl-C and a fresh start every
  correct stage takes one keypress, and the mistyped key is the only one to enter anew.
- **A terminal is required.** Without `/dev/tty` the script exits at once, so it cannot run under a
  pipe, in CI, or from pasted input. This is intended.
- **Line editing differs by prompt.** `ask` uses readline, so arrow keys move the cursor;
  `ask_secret` hides input and has no line editing. Backspace works in both.
- **A missing `gh` is expected.** CI-secret stages print a warning and add a closing-summary line
  naming each value the person still has to set themselves.
