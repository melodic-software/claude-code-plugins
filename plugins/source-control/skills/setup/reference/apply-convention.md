# `apply` — convention config (surface 1)

The full write path for the convention config: target-layer selection, the non-interactive
`subject_pattern=` write, the interactive interview, the written-file template, the per-layer
post-write verification, and the effective-merge report. Loaded from [SKILL.md](../SKILL.md)
"`apply` (idempotent)" — the hub owns *when* this runs; this spoke owns *how*.

**Pick the target layer first.** `layer=` selects it; `team` is the default when the argument is
absent, since a convention is a team artifact until someone says otherwise.

| `layer=` | Target path | For |
|---|---|---|
| `user` | `~/.claude/source-control.md` | the operator's own preference across every repo |
| `team` (default) | `REPO_ROOT/.claude/source-control.md` | the shared, tracked convention |
| `local` | `REPO_ROOT/.claude/source-control.local.md` | a personal deviation from team policy here |

Infer the layer rather than asking when the request names one — "my personal convention" / "on this
machine" is `local`, "for all my repos" is `user`, "our convention" is `team` — but state which
layer you picked before writing, since writing to the wrong one either fails to reach teammates or
commits a personal preference to shared history.

When the invocation carries a `subject_pattern=` argument, write non-interactively: use it as
`subject_pattern` (the literal `Conventional Commits` keyword, which resolves to the bundled 11-type
anchored pattern and enables `type_list`, or an anchored regex), and set `pr_title_pattern` to the
same. Reject a `subject_pattern` that is not machine-checkable (a plain-language value) with the same
message `check` gives, rather than persisting it.

**A non-interactive write is an update, not a fresh file.** The target layer is rewritten in place, so
read it first and carry through every *independent* key the invocation did not ask to change. An
argument naming `subject_pattern` says nothing about `trailer_policy`; dropping an existing
`trailer_policy: none` because the new invocation did not mention it changes commit behavior the user
never asked to change. Only a key the invocation explicitly sets may be replaced, and only a key the
user explicitly clears may be removed.

**Keys derived from a changed key are recomputed, not carried.** `type_list` and `pr_title_pattern`
are functions of `subject_pattern`, so preserving them across a `subject_pattern` change produces a
config that contradicts itself. Replacing a Conventional-Commits pattern with a custom regex drops
`type_list` entirely — a custom pattern has no type vocabulary, and a stale
`build, chore, ci, …` list beside `^[A-Z]+-\d+: .+` would have `/commit` pre-check against a
vocabulary the pattern does not use. Moving the other way re-adds the bundled 11-type list.
`pr_title_pattern` follows the same rule unless the user set it to a value independent of
`subject_pattern`, which is carried through like any other independent key.

**Writing an overlay layer — `user` or `local` — resolve the layers below first and omit any
*requested* key already equal to that merge.** A non-interactive argument is not evidence of a genuine
deviation: `apply layer=local subject_pattern=X` against a team file that already declares `X` would
otherwise pin `X` locally, so a later team change would be silently ignored on this machine — the
exact failure per-key override exists to prevent. This applies to the requested keys only; it never
licenses dropping an unrelated key the overlay already carries. When every requested key already holds
and the overlay would otherwise be empty, write nothing and say so rather than materializing an empty
file.

With no argument in an interactive session, run the interview:

0. **Anchor at the repo root** exactly as `check` does — resolve `REPO_ROOT` once and reuse the
   literal resolved path for every read, write, and git command below; re-resolve it at the top of
   every self-contained Bash call.
1. **Read the current config first** — all three layers, not just the target. Present the effective
   merge and which layer supplies each key; the interview proposes changes against that baseline and
   overwrites nothing without confirmation. Writing an overlay layer, carry only the keys that
   genuinely differ from the merge below it: an overlay that restates every key silently pins values
   the base layer should still own, which is the failure mode per-key override exists to avoid.
2. **Infer before asking.** Gate this on the resolved value, not on file presence: infer whenever the
   **effective merged `subject_pattern` is unresolved**, which includes the case where layers exist
   but contribute only other keys. Skipping inference because some file exists would recommend the
   bundled default over a `commit-msg` hook that demands ticket-prefixed subjects. Look for an
   existing declared or enforced convention, surfacing which signal produced the candidate:
   - The repo's own `CLAUDE.md`, `AGENTS.md`, or `.claude/rules` — prose stating a commit-message or
     PR-title convention.
   - A commit-msg git hook — `lefthook.yml` (`commit-msg` entry), `.husky/commit-msg`,
     `commitlint.config.*` / `.commitlintrc*` (and whether it extends
     `@commitlint/config-conventional` or declares custom rules), or a plain Git-managed `commit-msg`
     hook. Resolve the hooks directory with `git rev-parse --git-path hooks` rather than assuming
     `.git/hooks` — in a linked worktree `.git` is a file, not a directory, and the hooks directory
     (or a `core.hooksPath` override) can live elsewhere.
   - Commit-history consensus — the default history signal, a year-scale volume-weighted read, not
     a small fixed sample (a `-50` tail misses a convention shift and any informal variant family
     entirely). One pass:
     `git log --since="<window>" --no-merges --date=short --format='%cd|%s'` — subjects with an ISO
     date for the recency split; never `git log --oneline` (the abbreviated-hash prefix breaks
     anchored matching). `%cd` (committer date), not `%ad`: `--since` filters the walk by committer
     timestamp, so rendering author dates would let a rebased or cherry-picked commit enter the
     window yet land in the wrong recency bucket — one clock for both the filter and the split.
     Every knob is plugin `userConfig`, never a constant — a surviving literal
     `${user_config.…}` placeholder means the key is unset, so apply its manifest default:
     - `${user_config.setup_inference_window}` — the `--since` window (git-approxidate; default
       `1 year`).
     - `${user_config.setup_inference_recency_days}` — the recent-vs-older split boundary (default
       `90`).
     - `${user_config.setup_inference_min_commits}` — the low-confidence threshold (default `50`).
     Exclude auto-generated subjects before classifying: merges are gone via `--no-merges`; also
     drop `Revert`-, `fixup!`-, and `squash!`-prefixed subjects — auto-subjects restate other
     commits' shapes and would double-count them. Bucket-classify the survivors in-context —
     Conventional-Commits-shaped, ticket-prefix-shaped, informal near-variants of either (e.g.
     type-word without colon), other — and report volume-weighted percentages split at the recency
     boundary (e.g. `ticket-prefix 78.8% recent vs 71.9% older · Conventional Commits 0%`): a
     rising recent share is the live convention even when all-time volume says otherwise. Present
     the evidence table and let the user pick from it; never silently promote a bucket into config.
     Generic caveats — handle each and STATE it in the report whenever it applies:
     - **Shallow clone** (`git rev-parse --is-shallow-repository` → `true`): history is truncated —
       report the actual covered span rather than presenting a partial window as the full one.
     - **Young repo** (fewer classifiable subjects than the min-commits threshold): widen to full
       history; still below it, mark the inference low-confidence rather than authoritative.
     - **Squash-merge-only repo**: subjects ARE the PR titles — one signal, not two independently
       corroborating ones; say so when recommending both `subject_pattern` and `pr_title_pattern`
       from the same history.
   Present the inferred candidate as the recommendation, naming its source. If nothing is inferable,
   say so plainly and move to the interview with the bundled default as the recommendation.
3. **Interview, one decision at a time, recommendation first.** Ask: "What commit-subject / PR-title
   convention does this repo use?"
   - **RECOMMENDED: Conventional Commits**, 11-type vocabulary —
     `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test` — confirmed via the
     Conventional Commits spec, the Angular convention, commitlint's `@commitlint/config-conventional`
     source, and `amannn/action-semantic-pull-request`'s default `types` list. All four agree on this
     exact set; `security` is **not** a Conventional Commits type in any of them — never offer or
     accept it as a bundled type.
   - **Alternative: a custom pattern** — e.g. a ticket-prefix regex like `^[A-Z]+-\d+: .+` for orgs
     that don't use Conventional Commits at all. If step 2 inferred a custom pattern, present it as
     the recommendation instead.
   Let the user accept, edit, or supply something else. Do not invent a convention the repo gives no
   signal for and the user doesn't state.
   - **`subject_pattern` must always end up machine-checkable**: either the literal keyword
     `Conventional Commits`, or a single anchored regex (`^…$`-style, anchored at the start at
     minimum) that `/commit` and `/pull-request` can evaluate directly. If the user describes their
     convention in prose, translate it into an anchored regex yourself and confirm the translation
     before persisting — never write the prose. If a convention genuinely cannot be expressed as one
     regex, express the alternatives as alternation inside one anchored regex
     (`^(?:feat|fix): .+|^[A-Z]+-\d+: .+`), or fall back to the Conventional Commits default; do not
     persist a free-text `subject_pattern`, and never persist a list — `subject_pattern` is exactly
     one value, because nothing here defines how a list would serialize or match.
4. **Settle the remaining fields**, recommendation first:
   - **`pr_title_pattern`** — usually identical to `subject_pattern` (squash-merge repos set the PR
     title as the squash commit's subject). Ask only if the user wants them to differ; otherwise
     write the deferral marker exactly as `` Same as `subject_pattern`. `` — capital S, backticked key,
     trailing period. That literal is what the resolution contract recognizes and expands against the
     effective `subject_pattern`; any other casing or punctuation is read as a pattern in its own
     right and pre-checked as a regex.
   - **`trailer_policy`** (optional) — whether commits should carry a `Co-Authored-By:` (or other)
     attribution trailer, and its exact template. Recommend keeping `/commit`'s default unless the
     user states otherwise. Omit this section entirely if the repo has no trailer convention.
   - **`pr_body_attribution`** (optional) — the attribution line `/pull-request create` appends to the
     PR body, the PR-body analogue of `trailer_policy` and gated separately (a consumer setting
     `trailer_policy: none` still keeps the PR-body line unless this is also set). Recommend keeping the
     default `🤖 Generated with [Claude Code]…` line unless the user wants a custom line or `none` to
     omit it. Omit this section entirely to keep the default.
   - **`pr_body_required_sections`** (optional) — the required `## <heading>` section scaffold
     `/pull-request create` drafts and pre-checks before opening a PR (one bullet per heading; see
     [config-resolution.md](../../../reference/config-resolution.md) and
     [`docs/conventions/pr-body-convention/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pr-body-convention/README.md)).
     **RECOMMENDED: keep the plugin's own portable default** (`Summary`, `Test plan`) — this interview
     must not suggest a `Related`/linked-issue section, or any other specific organization's list, as
     if it were a universal default; a linked-issue section presumes an issue-tracker convention this
     plugin cannot assume for every repo. Ask what the repo's actual convention requires (a PR
     template, a CI gate like `pr-issue-linkage`, team practice) rather than proposing one, and write
     only what the repo genuinely needs. A repo whose convention is **no** PR-body sections states
     that as the literal keyword `none` (a resolved value overriding any lower layer's list, parallel
     to `trailer_policy`/`pr_body_attribution`) — omitting the section would inherit or fall through
     to the portable default instead.
     **Omitting this section does NOT always mean "use the portable default"** — per-key fallthrough
     (config-resolution.md's "Merge semantics") means an omitted section keeps whatever an *earlier*
     layer already resolves to. Check the effective merge from step 1 first: omit only when the layers
     *below* the one being written already resolve to the portable default (or the key is unset
     everywhere) — writing the explicit default there would just add redundant noise. When the intent
     is genuinely to reset back to the portable default *over* a lower layer that sets something else
     (a team config requiring `Related`, and this write is a personal overlay or a team rewrite meant
     to drop it), the portable default must be written out explicitly as the bullet list (`- Summary`,
     `- Test plan`) — an omitted section would silently keep inheriting the lower layer's list instead.
     State the one-line reason when this applies ("written explicitly to override the team layer's
     list, not merely to restate the default").
5. **Write the config.** Materialize the target layer's path with these sections:

   ```markdown
   # source-control configuration

   Read by the source-control Claude Code plugin (and, where installed, the guardrails
   commit-convention gate). Without those plugins this file is inert — safe to ignore.
   It is a drafting aid for plugin users, not team-wide enforcement: tool-agnostic
   enforcement for every committer (plugin or not) is a commit-msg hook or CI check.

   Commit-subject / PR-title convention for the source-control plugin, resolved by
   `/source-control:commit` and `/source-control:pull-request` before they infer from the repo's own
   CLAUDE.md/rules/commit-msg hook or fall back to the bundled Conventional Commits default.
   Re-run `/source-control:setup` to change these values.

   ## subject_pattern

   <the literal keyword `Conventional Commits`, or exactly one anchored regex — always
   machine-checkable, never a list and never a plain-language description>

   ## type_list

   <only present when subject_pattern is Conventional-Commits-shaped — omit this section entirely for
   a custom pattern with no type vocabulary>

   ## pr_title_pattern

   <the pattern, or "Same as `subject_pattern`.">

   ## trailer_policy

   <only present if the repo has a trailer convention>

   ## pr_body_attribution

   <only present if the repo overrides the default PR-body attribution line — a custom line, or
   `none` to omit it>

   ## pr_body_required_sections

   <only present if the repo's required-section scaffold differs from the plugin's portable default
   (Summary, Test plan) — a flat bullet list, one `- <H2 heading>` per line, e.g.:
   - Summary
   - Test plan
   - Related
   or the literal keyword `none` for a repo whose convention requires no PR-body sections>
   ```

   Drop any section with no content rather than leaving it empty. Writing a non-`team` layer, add one
   line under the heading naming which layer this file is and that it overrides per key — the file
   sits next to (or looks identical to) the team file, and the next reader has no other signal.

   The self-describing preamble above the first `##` heading exists for the reader who does NOT run
   these plugins — the team file lands in shared history, and a teammate opening it deserves to know
   it binds nothing on its own. It is part of the template, not an append: a reconfiguration run
   rewrites the whole header block in place, never stacks a second copy. Prose above the first H2 is
   inert to every consumer by construction — the enforcement resolver reads only the first non-empty
   body line under a `## <key>` heading (`lib/resolve-convention-pattern.sh` parse contract), and the
   drafting read is per-H2-key — so the preamble can never change a resolved value.

6. **Verify the write, per layer.** The post-write check inverts between layers and there is no
   shared shortcut: the team file must be tracked, the local overlay must be ignored, and the
   user-global file is not in a repository at all. Run the wrong one and the skill reports success
   over exactly the failure it exists to catch.

   - **`layer=user`** — `~/.claude/source-control.md` is outside `REPO_ROOT`. Run no git command
     against it: `git check-ignore` and `git status` on a path outside the worktree are meaningless
     here, and a home directory that happens to be its own repository would produce a confidently
     wrong verdict. Confirm the file exists with the intended content and report the path. It takes
     effect immediately in the next session; nothing is staged or committed.
   - **`layer=local`** — `REPO_ROOT/.claude/source-control.local.md` **must** be both ignore-matched
     and untracked, and those are two independent probes. Bare `git check-ignore` consults the index
     and reports nothing for a file that is already tracked, because gitignore rules do not apply to
     tracked files — so "no rule exists" and "a rule exists but the file was committed anyway" are
     indistinguishable from its output alone, and they need opposite remediations. Never stage the
     overlay in either case.
   - **`layer=team`** — `REPO_ROOT/.claude/source-control.md` must be tracked and staged. Verify it
     is actually staged before reporting success; neither `git check-ignore -v` nor
     `git ls-files --error-unmatch` proves this alone. `git check-ignore -v` only reports a matching
     `.gitignore` pattern, staying silent for both a properly tracked file and a plain untracked one.
     `git ls-files --error-unmatch` only proves the path is *somewhere* in the index: on a
     reconfiguration run (the file already existed and this step just rewrote it), the path was
     already tracked, so that check exits 0 even though the new content is still an unstaged
     working-tree modification.

   For `layer=team`, run these as one Bash tool call so `REPO_ROOT` only needs resolving once:

   ```bash
   REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
   # `git check-ignore -v` exits 0 (and prints the matching rule) only when a .gitignore pattern
   # excludes the file; it exits non-zero with no output otherwise. Branch on the exit code — do
   # NOT fall through to add/diff on a match: `git add` would silently refuse the ignored path, and
   # `git diff --quiet` on an ignored untracked file exits 0 trivially, so the sequence would report
   # false success with nothing actually staged for teammates.
   if IGNORE_MATCH="$(git check-ignore -v "$REPO_ROOT/.claude/source-control.md")"; then
     echo "STOP: .claude/source-control.md is excluded by .gitignore: $IGNORE_MATCH" >&2
     exit 1
   fi
   # With no ignore match, read the two-character XY status: `??` (untracked) or a non-blank
   # worktree (Y) column — a letter such as `M` in the second position, as in `XM`, `MM`, etc. —
   # means the just-written content is not yet staged.
   git -C "$REPO_ROOT" status --porcelain -- .claude/source-control.md
   # If unstaged (per the check above), stage it. This covers both the fresh-file case and the
   # reconfiguration case (an already-tracked file whose rewritten content hadn't been staged yet),
   # unlike an index-presence check alone.
   git -C "$REPO_ROOT" add .claude/source-control.md
   # Confirm nothing is left unstaged (exit 0 = worktree matches the index).
   git -C "$REPO_ROOT" diff --quiet -- .claude/source-control.md
   ```

   For `layer=local`, run both probes and branch on the pair:

   ```bash
   REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
   OVERLAY=".claude/source-control.local.md"
   # --no-index answers "does a matching ignore rule exist?" on its own terms. Without it, git
   # consults the index first and reports nothing for an already-tracked file, conflating a missing
   # rule with a rule that exists but was overridden by a past commit.
   IGNORE_MATCH="$(git -C "$REPO_ROOT" check-ignore --no-index -v -- "$OVERLAY")" && HAS_RULE=1 || HAS_RULE=0
   # An ignore rule does not untrack an already-committed file, so ask the index separately.
   TRACKED="$(git -C "$REPO_ROOT" ls-files -- "$OVERLAY")"
   # Exit non-zero on either FAIL, exactly as the team guard does. The overlay was written at step 5,
   # so proceeding here would report an effective merge over a personal file that is still shareable —
   # visible to `git status` (no rule) or already in team history (tracked). Halt until it is fixed.
   if [ "$HAS_RULE" -eq 1 ] && [ -z "$TRACKED" ]; then
     echo "OK: personal overlay is ignored and untracked: $IGNORE_MATCH"
   elif [ -n "$TRACKED" ]; then
     echo "FAIL: $OVERLAY is tracked; untrack it with: git rm --cached $OVERLAY" >&2
     exit 1
   else
     echo "FAIL: no ignore rule matches $OVERLAY; add .claude/*.local.* to .gitignore" >&2
     exit 1
   fi
   ```

   The tracked branch takes precedence in the report: adding the `.gitignore` line to an
   already-committed overlay changes nothing, so recommending it there sends the user in a circle.

   Either guard stopping the sequence (non-zero exit) halts the apply — do not report success or
   proceed to step 7. For the team guard (`IGNORE_MATCH` reported), tell the user the matching
   `.gitignore` pattern and ask them to either fix `.gitignore` so `.claude/source-control.md` is no
   longer excluded, or persist the convention to a different layer. For the `layer=local` guard,
   surface the failure's own remediation — the `.claude/*.local.*` ignore line for a missing rule, or
   `git rm --cached` for an already-tracked overlay — so the personal overlay does not linger in a
   shareable state. Re-run this step once the state is fixed.

   This skill stages but does not commit — `git status --porcelain` legitimately keeps printing an
   index (`X`) column of `A` or `M` with a blank worktree column for a staged-but-uncommitted file,
   so success does **not** require porcelain to be fully empty, only that no *unstaged* changes
   remain. Prompt the user to commit the team file, since it is team-shared and must be committed to
   take effect. Only report success once both checks pass: not ignored, and no unstaged changes
   remain.

7. **Report the new effective merge**, not just what was written. A `layer=user` write can be
   overridden by an existing team file, and a `layer=team` write can be overridden by an existing
   local overlay — a user who is told only "wrote `subject_pattern`" and then sees `/commit` use a
   different pattern has been misled by the success message.

   For a `team` write, the report also states plainly what the file is and is not: a drafting aid
   (plus CC-layer enforcement input) for teammates who run these plugins, inert for everyone else —
   NOT team-wide enforcement. Committers without the plugin are bound only by a commit-msg hook or CI
   check; when the team wants that, point at the guardrails plugin's opt-in commit-msg hook or the
   repo's own hook manager rather than implying this file enforces anything by itself.

## Neutral convention SSOT (`convention_source`)

For a `team` write, offer (never require) the neutral-file shape — one tool-agnostic flat-scalar
YAML file other consumers (commit-msg hooks, CI, other agents) read alongside this plugin. Contract
and value grammar are owned by the
[commit-convention seam](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/commit-convention/README.md);
this skill's part:

- **Offer it when it earns its keep** — the user says another tool consumes the convention (a hook,
  CI, another agent), or asks for a tool-agnostic/SSOT shape. A repo where only this plugin reads
  the convention loses nothing by staying markdown-only; say so rather than upselling the split.
- **Writing it:** ask the repo's own path preference (the plugin ships no doc-root convention —
  `docs/conventions/…`, `.github/…`, a root dotfile are all the repo's call; repo-relative,
  forward slashes, no `..`), write the YAML with machine keys (`subject_pattern`,
  `pr_title_pattern`, optionally `pr_body_required_sections`, `dialect: posix-ere`) plus `#`
  comments carrying the self-describing preamble, and declare `## convention_source` with that path
  in `.claude/source-control.md`.
- **Migration retires duplicates.** When the team markdown file already carries a key the neutral
  file now declares, REMOVE it from the markdown in the same apply — the resolver would prefer the
  neutral value anyway, but leaving both invites hand-edit drift, which is the disease this shape
  cures. Plugin-only keys (`trailer_policy`, `pr_body_attribution`) stay in the markdown file.
- **Verification adds one probe:** the pointer's target exists, is repo-relative, and round-trips
  through the enforcement resolver (`lib/resolve-convention-pattern.sh <repo_root>
  subject_pattern` emits the expected pattern). A broken pointer fails closed to no-enforcement by
  contract — surface it at write time, not at the team's first blocked commit.
