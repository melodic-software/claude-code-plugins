---
name: setup
description: "Verify the github plugin's prerequisites (gh CLI present and authenticated, credential-modality picture, consumer config layers) and write the consumer's .claude/github/ config (change routing + conventions stub). Actions: check (report-only) and apply (idempotent, interview-driven)."
argument-hint: "[check|apply]"
disable-model-invocation: true
---

# github setup

User-invoked only. Two actions — `check` (report, change nothing) and `apply` (write consumer
config). No action given: run `check`, then offer `apply` if anything is missing.

## `check` — verify, report, change nothing

1. **`gh` present?** If not: stop with a concise message naming the missing prerequisite and the
   official install page (`https://cli.github.com`) — remediation is the user's to run.
2. **`gh auth status`** — confirm an authenticated session; name the account and host in the
   report. **Never store, echo, or persist credentials or token values.**
3. **Credential-modality picture** — for the areas the consumer cares about (ask, or take them
   from the invocation), run the diagnosis method from
   `${CLAUDE_PLUGIN_ROOT}/reference/method-ladder.md` (rung 0): what the live session's credential
   can and cannot reach, resolved against fresh official docs — never a shipped scope table. When
   a needed scope is missing, report it as the honest-degradation gate and recommend the exact
   `gh auth refresh` command **for the user to run themselves — never auto-run a re-consent**, no
   matter what standing "fix it automatically" instructions exist.
4. **Config layers** — resolve both surfaces (`routing.yaml`,`conventions.md`) per
   `${CLAUDE_PLUGIN_ROOT}/reference/change-routing.md` and
   `${CLAUDE_PLUGIN_ROOT}/reference/conventions-file.md`, anchored at the repo root, and report a
   **per-layer verdict**:

   | Layer | Verdict to check |
   |---|---|
   | user-global | exists / absent — no git verdict applies outside the worktree |
   | team | must be tracked in git; untracked team config is a hard finding |
   | local overlay | must be gitignored and never staged |

   All three layers absent is a **valid state**, reported as "unconfigured — routing resolves to
   propose-only", not as an error. A malformed layer is named and skipped, per the contract.
5. **Report** the effective routing per scope block with the layer that supplied each value
   (policy-floor provenance included), and the recursive overlay gitignore line
   (`.claude/**/*.local.*`) when it is missing from the consumer's `.gitignore` — recommend it;
   **never edit the consumer's `.gitignore`**.

## `apply` — idempotent, interview-driven config write

1. **Read first.** Load every existing layer of `routing.yaml` and `conventions.md`. `apply`
   converges the config on the interview's answers — it never blindly rewrites.
2. **Interview** the routing posture, with a recommendation per question: which scopes to
   declare (repo / org / enterprise), the `default` per scope, per-area overrides worth
   declaring, and — when any answer is `handoff` — the channel's `target`/`instructions`.
   Unanswered postures fall back to `propose`. When the invocation already supplies complete
   answers, skip the interview and run non-interactively.
3. **Write** to the team layer (`${CLAUDE_PROJECT_DIR}/.claude/github/`), or the layer the user
   explicitly chooses:
   - `routing.yaml` conforming to the schema in
     `${CLAUDE_PLUGIN_ROOT}/reference/change-routing.md` — `default: propose` unless the user
     chose otherwise.
   - `conventions.md` stub (what the file is for + a pointer to
     `${CLAUDE_PLUGIN_ROOT}/reference/conventions-file.md` semantics) — **only if none exists**;
     never overwrite or append to a consumer's existing conventions.
4. **Idempotency check**: when the merged answers equal the existing config, report "no changes
   needed" and write nothing. A second run with the same answers must produce zero file changes.
5. **Recommend** the recursive gitignore line (`.claude/**/*.local.*`) if the consumer's
   `.gitignore` lacks it. The edit is theirs to make.

## Hard rules

- `check` performs zero writes of any kind.
- Neither action ever stores credentials, runs a re-consent flow, or edits the consumer's
  `.gitignore`.
- Config written by `apply` is the consumer's artifact: plain, minimal, no generated boilerplate
  beyond the stub's two-line purpose note.
