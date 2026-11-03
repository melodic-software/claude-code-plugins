# 2.4.3 Create PR

Part of [Phase 2: Create](create.md), which lists every section's file; a bare § number names a section listed there.

**PR states.** Each state has one meaning:

- **Save point:** commits pushed to the feature branch, with no PR. Pushing is how work is saved;
  a PR is never opened only to save it.
- **Draft:** a PR a person asked to see early, or a multi-session container (a PR later sessions
  will keep adding to before it is complete); both carry a `Draft:` body line that holds them
  against unattended flips. A PR also stays a draft while it waits for `ready`: under the `draft`
  open state, or when one of `ready`'s holds or gates stops the flip.
- **Ready:** complete and through the local gates, which `/source-control:pull-request ready`
  runs before it flips the PR ([ready-for-review.md](ready-for-review.md)). Ready is what starts
  the test lanes, the AI reviews and code-owner review requests.

**Resolve the open state first.** `pr_open_state` decides whether the PR stays a draft. Its
levels are in [../../../reference/config-resolution.md](../../../reference/config-resolution.md),
"YAML keys"; read it yourself, since no script resolves it:

0. **Request.** When the invocation asks for a draft (the user or the calling prompt asks for a
   draft or to show the work early, says the PR is a multi-session container, or passes
   `--draft '<reason>'`), the state is `draft` and the level is `request`, whatever the levels
   below say. Record it in the body as its own last line before the attribution: `Draft:
   requested early look`, `Draft: multi-session container`, or `Draft: <reason>` for the flag.
   That line tells unattended flippers the draft is a person's choice; only a person removes it
   or flips the PR.
1. **Repository level.** When [§2.4.1](create-push-and-body.md)'s `<plugin-root>/lib/config-root.sh classify` printed `repo`, read
   `docs/conventions/source-control.yaml` at the PR's base branch in the base repository, never
   from the working tree or the branch being opened, the same way the review-bot rubric is read
   ([config-resolution.md](../../../reference/config-resolution.md#review-bot-triage-rubric-docsconventionssource-controlmd);
   [GitHub](../../../reference/providers/github/pull-request/create.md#read-the-open-state-at-the-base-branch)).
   The head branch is the change under review, so a value it sets would let the change choose its
   own state. A 404 means the
   level is unset. If the file has a top-level `pr_open_state:` key, its value (quotes and a
   trailing `# comment` removed) wins. Report the level as `repository
   (docs/conventions/source-control.yaml at <base-branch>)`.
2. **Per-user level.** Otherwise take the substituted value from SKILL.md's "PR open state" line.
   A substituted `draft` reports the level as `userConfig`; any other value except `ready` is an
   invalid value at `userConfig`.
3. **Default.** Otherwise, meaning a substituted `ready` or the unsubstituted token, the state is
   `ready` and the level is `default`. A consumer opts into `draft` at the per-user or repository
   level.

A value other than `draft` or `ready` at the level that supplied it is not used: say which level
held which value, take the state as `draft`, and report the level as `invalid value at <level>
(fell back to draft)`.

**An unattended run follows the resolved state.** A loop lane, a CI lane, a `dontAsk` session, a
worker or orchestrator dispatched by another skill, and every `--pushed` run resolve the state the
same way an attended run does. A resolved `ready` runs Phase 2.5 as `ready --unattended`, whose
holds still apply: a `Draft:` body line, a superseded item or a failed gate leaves the PR a draft
and [§2.6](create-report.md) reports why.

**Every state opens as a draft; `ready` is reached by the flip.** The commands below always open
a draft. When the state resolves to `ready`, run Phase 2.5 ([ready-for-review.md](ready-for-review.md))
on this PR to completion right after [§2.5](create-ci-workflows.md), so the PR reaches ready only through `ready`'s gates.
When one of them stops, the PR stays a draft and §2.6 reports why. Inside `full`, skip this:
`full` runs Phase 2.5 itself after its create checkpoint.

Append `${ATTRIBUTION}` (resolved in §2.4.1) to `$BODY_FILE` only now, after both [§2.4.2](create-gate.md) gates
passed against the attribution-free body, never earlier (§2.4.1's note says why):

```bash
# Spliced by parameter expansion as a printf argument, never a format string or a
# heredoc, so a `$`-bearing configured ATTRIBUTION value is never re-evaluated.
[[ -n "$ATTRIBUTION" ]] && printf '\n\n%s\n' "$ATTRIBUTION" >>"$BODY_FILE"

# Read the branch from the checkout §2.4.1 pushed (the same literal absolute
# path), never the cwd, which can reset to the main checkout.
BRANCH=$(git -C "<checkout>" branch --show-current)
if [[ -z "$BRANCH" ]]; then
  echo "create: '<checkout>' is not on a named branch (detached HEAD?); not creating a PR" >&2
  exit 1
fi
# push-branch.sh's own check, pushing nothing: refuses main, master, the push
# remote's default branch as the remote reports it, and an unreadable default.
bash "<skill-dir>/scripts/push-branch.sh" --check --dir "<checkout>" "$BRANCH" || exit 1
```

Then open the PR as a draft from head `$BRANCH`, with the title and the body file, and capture `PR_URL` and `PR_NUMBER`
([GitHub](../../../reference/providers/github/pull-request/create.md#open-the-draft-pr)). That
number is the source of truth for the rest of this phase: pass it explicitly to every later forge
call.

- **Identity:** the human PR author by default. If the consuming project routes automation writes
  through a bot identity wrapper, use it for comments and reactions; the human account normally
  authors the PR itself.
- **No reviewers are auto-requested by default.** Reviews come from the AI reviewers the repo wires
  up and any humans who opt in.
- **Title shape:** whatever the resolved subject/title convention requires (Conventional Commits
  default shown; a custom resolved `pr_title_pattern` or the project's own convention overrides
  it).
- **Open state:** always a draft at creation (`ready` flips it when the state resolves to `ready`). A draft owes no review: review lanes that filter
  drafts skip it, so opening ready for review would claim a review that has not happened.
  `/source-control:pull-request ready` performs the flip ([ready-for-review.md](ready-for-review.md)).

**Sandboxed sessions: open the PR over REST.** The CLI's PR create sends a GraphQL query before touching the pull-request API, so under [§2.4.0](create-linked-issue.md)'s GraphQL restriction it returns `HTTP 403` having created nothing. The REST pull-request endpoint works, with these differences: the base branch must be passed (resolved over REST as well, since [§2.2](create-rebase.md)'s repository read 403s alongside the rest), a head from a fork must be namespaced `<fork-owner>:<branch>`, the body is sent from its file, `draft` is sent as a boolean, and the response carries the PR number and URL ([GitHub](../../../reference/providers/github/pull-request/create.md#open-the-pr-over-rest)). Placeholder expansion and the out-of-tree anchoring rule are as stated in §2.4.0, and apply to both of its calls.

**The REST form has no hook backstop.** `pr-body-linkage-gate.sh` matches the CLI's PR create and edit commands and names the REST pulls call among the invocations it deliberately does not see, so this path bypasses it. Inside this skill that costs nothing: §2.4.2's gates already ran against `$BODY_FILE`, which is why they, not the hook, are the authority. A REST PR opened *outside* the skill has no second check; the repository's own PR-contract check is then the first to notice a missing closing keyword or an empty required section.

PR identity (number + URL) is queried live from the forge, the authoritative source, whenever a later phase needs it ([GitHub](../../../reference/providers/github/pull-request/create.md#pr-identity)); never persisted to a state file. That read is GraphQL-backed, so a sandboxed session under the restriction above takes identity from the create response, or re-reads it over REST.

**All subsequent phases MUST use `<pr_number>` explicitly**, never a bare PR view, checks or merge call without the PR number argument.
