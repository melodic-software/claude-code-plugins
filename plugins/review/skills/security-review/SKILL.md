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
in this PR: use `gh pr diff` to see what changed, then read those files. Reading a changed
plugin's files to find the code that consumes a changed `userConfig` key is in scope. Do not
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

**Plugin manifests.** A change to a `.claude-plugin/plugin.json` or `.claude-plugin/marketplace.json`
can switch a control off or install code without touching a script, so such a diff is never
eligible for skip 2. Compare the base and head manifests:

- A `userConfig` key is a guard when the code that reads it gates, caps, confirms, limits, or
  costs something; judge by that code, never by the key's name. A guard whose `default` changes in
  the direction that widens unchecked action (a gate turned off, an autonomy tier or unlimited
  mode turned on, a cap or budget raised), or that is removed, is a finding: every user who never
  set it gets the wider action on update. Name the control and the action that now reaches it
  unchecked. An added key that is a guard (judged by the code or skill text that reads it) whose
  default is the permissive value is a finding. A change that lowers a value's protection is a
  finding too.
- Default deny. Every other field added, changed, or removed is a `manifest <field>: flag`,
  whatever the lane believes about it, unless it is in this repository's inert set:
  `description`, `keywords`, `author`, `homepage`, `repository`, `license`, a marketplace
  entry's `tags` and `category`, a `userConfig` key's `title` and `description`, and a changed
  (not added or removed) `version`. On each such flag, name in the summary what runs and where it comes from (the command, server, or script, and the
  path, package, or URL with its pin), or what installed users get on update. A source outside
  the repository with no pin, a command fed consumer-controlled input, or a tool grant wider than
  the command needs also gets its exploit path.

For each item the diff hits, the summary carries one line, `manifest <field>: pass` or
`manifest <field>: flag, <reason>`, so the outcome reads without the inline comments. Every
`flag` line is a finding: it counts in the review's findings total, which is what holds the merge.

The pointers below are reading material for naming what a flagged field runs, never the test
for whether it is flagged. Pointer: what each field loads, runs, grants, or stores is read at
[plugin manifest reference: Fields](https://code.claude.com/docs/en/plugins-reference#fields),
[Component path forms](https://code.claude.com/docs/en/plugins-reference#component-path-forms),
[User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration), and
[Channels](https://code.claude.com/docs/en/plugins-reference#channels). As of: 2026-10-21.
Recheck trigger: any of those sections changes.

## High-signal bar

Exclude pre-existing issues, linter-catchable noise, and generic security advice
without a concrete exploitable path in this diff. Each finding gives the file and
line, why it is wrong, and that exploit path: the input or request that shows it
failing. Committable suggestion fences
(GitHub `suggestion` code blocks) only when the suggestion alone fully fixes the
anchored finding. A `manifest <field>: flag` line is exempt from this bar: it counts as a finding
with or without an exploit path.

## Adversarial validation

When fanning out hunters, validate each surviving candidate with a separate
verifier subagent (producer ≠ verifier). Dispatch every hunter and verifier as
the `review:lane-verifier` agent, never a general-purpose subagent, so no
subagent can re-invoke this skill and fan out. Drop rejected candidates, except a
`manifest <field>: flag` line, which a verifier never drops: the diff hitting the item is the
evidence.

## Reporting

Use the inline-comment tool the wrapper granted to anchor each finding to the
changed line it concerns. Cross-file / whole-PR findings go in the summary with
commit-blob permalinks using the supplied HEAD SHA.
