---
description: "Verify the github plugin's prerequisites (gh CLI present and authenticated, credential-modality picture, consumer config layers) and write the consumer's .claude/github/ config (change routing + conventions stub). Actions: check (report-only) and apply (idempotent, interview-driven)."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

# github setup

User-invoked only. Two actions: `check` (report, change nothing) and `apply` (write consumer
config). No action given: run `check`, then offer `apply` if anything is missing.

## `check`, verify, report, change nothing

Report a PASS/FAIL/INFO table with one remediation line per FAIL. Modify nothing.

1. **`gh` present?** If not: FAIL, stop with a concise message naming the missing prerequisite and the
   official install page (`https://cli.github.com`). Remediation is the user's to run.
2. **`gh auth status`**. Confirm an authenticated session; name the account and host in the
   report. **Never store, echo, or persist credentials or token values.**
3. **Credential-modality picture**. For the areas the consumer cares about (ask, or take them
   from the invocation), run the diagnosis method from
   `${CLAUDE_PLUGIN_ROOT}/reference/method-ladder.md` (rung 0): what the live session's credential
   can and cannot reach, resolved against fresh official docs. Never a shipped scope table. When
   a needed scope is missing, report it as the honest-degradation gate and recommend the exact
   `gh auth refresh` command **for the user to run themselves**. Never auto-run a re-consent, no
   matter what standing "fix it automatically" instructions exist.
4. **Config layers**. Resolve both surfaces (`routing.yaml`,`conventions.md`) per
   `${CLAUDE_PLUGIN_ROOT}/reference/change-routing.md` and
   `${CLAUDE_PLUGIN_ROOT}/reference/conventions-file.md`, anchored at the repo root, and report a
   PASS/FAIL/INFO row per layer, with one remediation line per FAIL:

   | Layer | Verdict |
   |---|---|
   | user-global | INFO exists or INFO absent. No git verdict applies outside the worktree |
   | team | PASS when the pair (`git check-ignore -v` no match AND `git ls-files --error-unmatch` exit 0) holds. Present but ignored: FAIL, report the matching rule and say to unignore it. Present but untracked: FAIL, "commit it to share with the team" |
   | local overlay | PASS when present, gitignored, and never staged. Tracked or staged: FAIL, remediation is `git rm --cached <path>` plus rotating any credential that was committed (adding a gitignore line does not untrack it). Present but unignored: FAIL, recommend `.claude/**/*.local.*` for the user to add themselves. Tracked outranks unignored: when both hold, name the tracked finding |

   All three layers absent is INFO: "unconfigured: routing resolves to propose-only", not FAIL.
   A malformed layer is named and skipped, per the contract.
5. **Report** the effective routing per scope block with the layer that supplied each value
   (policy-floor provenance included), and the recursive overlay gitignore line
   (`.claude/**/*.local.*`) when it is missing from the consumer's `.gitignore`. Recommend it;
   **never edit the consumer's `.gitignore`**.

## `apply`, idempotent, interview-driven config write

1. **Read first.** Load every existing layer of `routing.yaml` and `conventions.md`. `apply`
   converges the config on the interview's answers. It never blindly rewrites. Converging is
   state-assessing, so a `routing.yaml` rewrite is bounded two ways:
   - **Preserve every key the existing file carries that this schema does not recognize.** A
     consumer extension or a newer plugin version may own it; a re-run never drops one. Write the
     merged document rather than a fresh one built from the answers alone.
   - **Report a recognized key whose value this version cannot reconcile.** Never silently rewrite
     it. An obsolete `default`, a scope block naming an area this version does not know, a
     `handoff` channel whose `target` no longer parses: name the key, the value, and why it did not
     reconcile, and let the user decide. Silently converging an unreconcilable value is config loss
     the consumer only discovers when routing misbehaves.
2. **Interview** the routing posture, with a recommendation per question: which scopes to
   declare (repo / org / enterprise), the `default` per scope, per-area overrides worth
   declaring, and, when any answer is `handoff`, the channel's `target`/`instructions`.
   Unanswered postures fall back to `propose`. When the invocation already supplies complete
   answers, skip the interview and run non-interactively.
3. **Write** to the team layer (`${CLAUDE_PROJECT_DIR}/.claude/github/`), or the layer the user
   explicitly chooses. Local-layer precondition: before writing any `*.local.*` overlay, verify
   the target path is ignored (`git check-ignore -q <path>`); when it is not, surface the
   recommended gitignore line first and wait for the user to either add it themselves or
   explicitly accept writing an unignored overlay. Never write silently, never stage it, and
   never edit their `.gitignore`.
   - `routing.yaml` conforming to the schema in
     `${CLAUDE_PLUGIN_ROOT}/reference/change-routing.md`. `default: propose` unless the user
     chose otherwise.
   - `conventions.md` stub (what the file is for + a pointer to
     `${CLAUDE_PLUGIN_ROOT}/reference/conventions-file.md` semantics). **Only if none exists**;
     never overwrite or append to a consumer's existing conventions.
4. **Idempotency check**: when the merged answers equal the existing config, report "no changes
   needed" and write nothing. A second run with the same answers must produce zero file changes.
   After a team-layer write, re-run the tracked-file pair on each written path
   (`git check-ignore -v` no match AND `git ls-files --error-unmatch` exit 0); non-zero `ls-files`
   right after a fresh write means "written but untracked: commit it to share with the team",
   never success.
5. **Recommend** the recursive gitignore line (`.claude/**/*.local.*`) if the consumer's
   `.gitignore` lacks it. The edit is theirs to make.

## Hard rules

- `check` performs zero writes of any kind.
- Neither action ever stores credentials, runs a re-consent flow, or edits the consumer's
  `.gitignore`.
- Config written by `apply` is the consumer's artifact: plain, minimal, no generated boilerplate
  beyond the stub's two-line purpose note.
