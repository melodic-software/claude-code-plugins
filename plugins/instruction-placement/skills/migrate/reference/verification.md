# Verifying a migrated repository

Worked detail for the migrate skill's "Verify the load" step. The rule the hub states is the whole
point of this file: **nothing here is assumed, and `UNKNOWN` is never a pass.**

## `verify-load.sh`, per surface

Every invocation carries `--root`, for the same reason the plan command does: a shell's working
directory does not survive between tool calls.

```bash
# The root file, through its shim. <trigger> is any tracked file that exists.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-load.sh" \
  --root <repo> --trigger README.md --expect AGENTS.md

# A nested surface: the trigger has to be a file IN that directory, because the
# nested attach fires on a Read there and nowhere else.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-load.sh" \
  --root <repo> --trigger src/billing/service.ts \
  --expect AGENTS.md --expect src/billing/AGENTS.md

# A path-scoped rule: the trigger is a file its `paths:` glob matches.
bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-load.sh" \
  --root <repo> --trigger src/api/handler.ts --expect .claude/rules/api.md
```

It drives one real `claude -p` turn with an `InstructionsLoaded` hook and prints
`VERDICT PASS|FAIL|UNKNOWN`. **`UNKNOWN` (exit 3) is a third outcome, never a pass**: the probe
could not measure, so rerun once and escalate if it stays `UNKNOWN`.

## The root case, before and after

For an `agents-only` repository the shim is the whole change, and `reachable` is the root-level
parallel of `wiring`. Capture both readings:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh" reachable --file AGENTS.md --root <repo>
```

`NATIVE` before the shim (nothing blocks the file, and nothing carries it into a session that
cannot read `AGENTS.md` directly), `LOADED` after it. Put both lines in the PR body: they are the
static half of the evidence, and the canaries are the empirical half.

## The canary token

**Put the token in its own paragraph directly under the file's first heading.** Never under a
pointer-only section: a pointer's body is a sentence about another file, so a token there tests
whether that sentence loaded, which nobody asked.

A canary counts only against a **non-empty** `AGENTS.md`. An empty file passes every canary and
carries nothing.

The token lives in the working tree and never in a commit, so the order is: commit the migration,
add the token, run the canaries, remove the token. Afterwards `git status --porcelain` is clean and
`git grep -c CANARY` **prints nothing and exits 1** — that exit is the success signal for a
no-match grep, not a failure, and a caller gating on exit codes has to know it. Checking for a
clean tree *before* the canaries can never pass: the tree is dirty by construction while they run.

## Asking Claude

```bash
claude -p "Read the file <a file in that directory>. Then quote back, verbatim, every line of your
  project instructions that contains the word CANARY. If there are none, say NONE." \
  --model haiku --allowedTools Read
```

**Ask for the lines, and name a file that exists.** "List every canary token in your instructions"
reads as an exfiltration request and gets refused, which proves nothing about the loader; and a
Read of a missing file never fires the nested trigger the canary is testing.

## Asking Codex

Codex is a first-class target of this migration, so it gets the same canary. Presence-gate it on
the CLI (`command -v codex`); where Codex is absent, say the leg was not run rather than treating
it as passed.

```bash
codex exec -C <repo> "Read the file <a file in that directory>. Then quote back, verbatim, every
  line of your project instructions that contains the word CANARY. If there are none, say NONE."
```

Then confirm in the session rollout that **no shell command went looking for the token**. A run
that greps its way to the answer proves the file is on disk, which was never in doubt, and not that
Codex loaded it.

- **Claim**: Codex writes a session rollout to
  `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. A shell call appears as a JSONL record whose
  `payload.type` is `custom_tool_call`, with the command inside `payload.input`; one run observed
  it as `exec_command` instead, so match either. Two rollout files can land a second apart, so
  pick the one whose records contain the prompt rather than the newest by mtime.
- **Basis**: observed on codex-cli 0.155.1 across the migration runs that produced this file.
- **As of**: 2026-09-19.
- **Recheck trigger**: a codex-cli release that changes the session-file layout, the record type,
  or where rollouts are written.

Codex's project-doc budget is cumulative and can silently drop a file past it. The number and its
dated record are beside `CODEX_PROJECT_DOC_BUDGET` in `scripts/plan-migration.sh`; the `BUDGET`
rows say whether this repository is near it.

## Progressive disclosure, with a caveat

Run `/docs-hygiene:audit-progressive-disclosure` via the Skill tool, when it is installed, on the
finished root `AGENTS.md`: a root file that grew during the migration has moved the cost rather
than removed it.

**Hand-check its tier and pointer facts before acting on a finding.** That detector currently
labels a root `AGENTS.md` `tier=invocation` rather than an always-loaded surface, and counts only
markdown-link pointers, so a backticked path reads as no pointer at all. Both make its verdict on a
migrated root file unreliable in a direction that looks like a real finding (#4292).
