---
description: "CI security-review lane for a GitHub pull request. Logic, trust-boundary, and Actions security findings static analysis misses. When the plugin-backed built-in security-review command resolves in this session, prefer it for a one-off security pass over the current branch; this skill for the CI lane a reusable workflow runs on one PR. Use when: 'CI security review', 'claude-security-review lane', '/review:security-review', or a reusable workflow invokes the org security-review plugin command."
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(gh pr diff:*)", "Bash(gh pr view:*)", "Bash(gh pr comment:*)", "Bash(gh pr review:*)", "Read", "Glob", "Grep"]
metadata:
  workflow-stage: review
  summary: Org CI security-review lane command for a GitHub pull request
---

# CI security review (`/review:security-review`)

Org-owned security review logic for the `claude-security-review` reusable
workflow. We treat built-in `/security-review` as unusable in CI: it cannot post, and the
Actions checkout leaves it without the diff base it needs. Pointer: why it fails there is read at
[errors: /security-review fails without origin/HEAD](https://code.claude.com/docs/en/errors#security-review-fails-without-origin-head).
As of: 2026-10-11. Recheck trigger: that entry stops naming CI checkouts, the command gains a diff
base a CI checkout provides, or a release note names `/security-review`. This org-authored skill is
the CI path. The lane wrapper supplies `REPO` /
`PR NUMBER` / `HEAD SHA` and installs the inline-comment MCP server via
`claude_args`; this skill owns **what to hunt for**.

## Boundary, the native `security-review` command

One native Claude Code surface shares this lane's name, and the two get conflated on any open pull
request:

- **`security-review` (native command)**: the installed binary registers it plugin-backed, and the
  commands table gives it no Skill label. A developer runs it in their session for a single security
  pass over the current branch, with no PR target this lane could hand it. Pointer: the first row
  of
  [reference/bundled-security-review.md](reference/bundled-security-review.md#the-native-security-review-command-verification-record)
  carries that record. As of: 2026-10-11. Recheck trigger: that row moves or stops carrying its own
  pointer and trigger. It cannot run under the Actions checkout (the opening paragraph carries that
  record).
- **This skill (marketplace plugin).** The security logic the `claude-security-review` reusable
  workflow runs in CI. The wrapper supplies the target and owns posting; this skill owns what to
  hunt for.

**Routing.** This skill runs in two modes: the CI lane, where the reusable workflow invokes it,
and seat-run mode, where the pull-request skill's ready step or the operator invokes it directly
(the section below). In a session, when the native command resolves, prefer it for an ad-hoc
pass before a pull request exists; the run a repository's mandatory-skill map asks for by name
is this skill, not that command, because the two stamp different names into the skill-usage
ledger a map reads. A deep multi-agent scan or repository monitoring is neither surface: those
are the Claude Security plugin and product.

**Mutation gate.** In the CI lane this skill posts only through its wrapper's mechanics; in
seat-run mode it posts nothing at all. It edits nothing in either mode, so never invoke the
native command on this lane's behalf.

**Availability is never assumed.** Native surfaces are gated by their backing plugin, settings,
environment, and host; this section states what to do when one resolves, never that it is
present. The four-part records live in
[reference/bundled-security-review.md](reference/bundled-security-review.md).

## Seat-run mode

The same criteria run outside CI, on the operator's own session: invoked by the pull-request
skill's ready step, or by hand against an open pull request. No wrapper supplies the inputs
there, so read them:

- `gh pr view <n> --json number,headRefOid` for the number and the head SHA. REST serves both,
  so no checkout with history is needed.
- `gh pr diff <n>` for the diff, or `gh api repos/{owner}/{repo}/pulls/<n>/files --paginate`
  when per-file entries are wanted instead of one patch.

Return the findings in the conversation, in the same severity vocabulary
(CRITICAL / IMPORTANT / SUGGESTION) and against the same high-signal bar. Post nothing to
GitHub: no review, no comment, no label. The inline-comment MCP server is a wrapper grant the
CI lane alone gets, so it is not used here; on the seat the transcript is the report.

## Gotchas

- This skill's frontmatter does not install the inline-comment MCP server; the action's
  `claude_args` does. Rely on the wrapper grant. Pointer: the keys skill frontmatter accepts are
  read at [skills: frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference).
  As of: 2026-10-11. Recheck trigger: that section adds a key that declares an MCP server.
- Report **security issues only**. No style, naming, test-coverage, or general
  code-quality commentary (that is `/review:code-review`).

## Skip gate (cheap)

Before deep review, stop early when any of these hold (say so plainly and post
nothing else):

1. PR is closed or not open
2. Change has no security-relevant surface after reading the diff. A diff that deletes, narrows,
   or softens a standing instruction is not eligible for this skip until it has been read under
   the instruction-surface lens below: it reads as prose-only while it can remove a control
3. This head already has a successful security review that still applies

## Criteria

Perform a security review of THIS pull request. Review ONLY the files changed
in this PR: use `gh pr diff` to see what changed, then read those files. Do not
audit unrelated parts of the codebase.

Hunt for vulnerabilities that static analysis misses: logic flaws, authorization
and access-control gaps, injection surfaces (command, SQL, path, template), and
unsafe handling of tokens / secrets / credentials. Tag each finding with a
severity (CRITICAL / IMPORTANT / SUGGESTION).

GitHub Actions hardening is zizmor's advisory lane: dangerous triggers such as
`pull_request_target` or `workflow_run` running untrusted code with secrets,
expression injection through the `github` context inside `run:` blocks,
permission-widening changes to a workflow's `permissions:` or to settings /
config, and supply-chain risk from loosened or unpinned action / dependency
pins. Defer to it and do not re-report those findings here. This lane's value
is the logic, architecture, data-flow, and trust-boundary security reasoning
static analysis cannot reach, so report an Actions finding only when it needs
that reasoning. If you find no security issues, say so plainly.

**Instruction-surface deletions.** Removing a guardrail makes the surrounding context the model's
only judgment input, and a hostile context then decides what the removed rule used to. When the
diff deletes, narrows, or softens a standing instruction (`CLAUDE.md`, `AGENTS.md`, a rules file,
a skill or agent body, a hook's block list or allowlist), check each removed rule against the
protected classes in the
[instruction exception register](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/instruction-exception-register/README.md).
Recognition is by consequence, not phrasing: ask what breaks when the rule is absent at the moment
it was written for. A match is a finding when nothing else in the tree still enforces it, such as
a hook, a permission deny rule, or a validator. Name the class, the action the rule prevented, and
the request that now reaches that action with no check. That is this lane's exploit path. A rule
that a mechanism still enforces is not a finding, and neither is one the diff compresses without
changing what it forbids. The register URL is not readable with this skill's granted tools (no
WebFetch) and the file may be absent from the checkout, so read
`docs/conventions/instruction-exception-register/README.md` when it is present, and when it is not,
fall back to recognition by consequence and say in the review that the protected-class list was not
consulted. The `security-reviewer` agent behind
`/review:quality-gate` security mode and `/review:fanout` carries the same lens as a pointer, so
local and CI review judge such a diff by the same register.

## High-signal bar

Exclude pre-existing issues, linter-catchable noise, and generic security advice
without a concrete exploitable path in this diff. Each finding gives the file and
line, why it is wrong, and that exploit path: the input or request that shows it
failing. Committable suggestion fences
(GitHub `suggestion` code blocks) only when the suggestion alone fully fixes the
anchored finding.

## Converge across rounds

A pull request this lane reviews more than once must converge, not draw a fresh set of findings
every push. Before hunting, read what this lane already posted on the PR (its review bodies and
summary comments, `gh pr view <n> --json reviews,comments`) and count its earlier rounds. Seat-run
mode applies the same rules to the findings already in the conversation.

- **First round reviews the whole PR; later rounds review only the new diff.** After the first
  round, hunt only in the changes since the head this lane last reviewed. When the wrapper narrows
  the scope to those files, keep to it.
- **No repeats.** Never post a finding this lane already posted, open or resolved, unless the new
  diff changed the code it names. Refer to the earlier finding instead.
- **Flag the class, not one instance.** When a finding is one case of a repeatable flaw (the same
  unvalidated input, the same missing authorization check), name the class once, list every
  instance in the diff, and say where else it can occur.
- **Cap: three rounds, then escalate.** From the fourth round on, post no new SUGGESTION findings.
  A new CRITICAL or IMPORTANT finding is still reported, never held by the cap: say in the summary
  that the cap is reached and that the open security findings need a person to decide.

Pointer: the convergence practice these rules follow is read at
[Solving code review at Anthropic: how we make the reviewer better](https://claude.dev/blog/solving-code-review-at-anthropic/#how-we-make-the-reviewer-better),
its "Review has to converge" paragraph. As of: 2026-10-17. Recheck trigger: that paragraph changes
its round cap or its re-review scope.

## Adversarial validation

When fanning out hunters, validate each surviving candidate with a separate
verifier subagent (producer ≠ verifier). Dispatch every hunter and verifier as
the `review:lane-verifier` agent, never a general-purpose subagent, so no
subagent can re-invoke this skill and fan out. Drop rejected candidates.

## Reporting

Use the inline-comment tool the wrapper granted to anchor each finding to the
changed line it concerns. Cross-file / whole-PR findings go in the summary with
commit-blob permalinks using the supplied HEAD SHA.
