# 2.4.0 Resolve linked issue(s)

Part of [Phase 2: Create](create.md), which lists every section's file; a bare § number names a section listed there.

Before building the PR body, resolve the work item the branch names and its link line (injected at the top of the body in [§2.4.1](create-push-and-body.md)), and prompt for any additional links. With a work-item tracker bound, its adapter owns the link text and the default branch grammar (the tracker-bound path below); otherwise the GitHub default applies.

The parser resolves the grammar itself: the `branch_issue_pattern` key across the layers (the team YAML `docs/conventions/source-control.yaml`, then the legacy `source-control.md` for a key the YAML lacks; add `--explain` to print the supplying layer on stderr), then the deprecated userConfig value passed below, then the built-in `<type>/<N>-<slug>` (and `routine-issue-<N>`) convention:

```bash
ISSUE_NUM=$(bash "<skill-dir>/scripts/parse-branch-issue.sh" || true)
```

If SKILL.md's "Branch-to-issue grammar" surface shows a configured `branch_issue_pattern` userConfig value (a real ERE, not the literal `${user_config…}` token; this file is Read raw, so the value resolves there, never here), pass it as a **single-quoted** second positional (shielding ERE metacharacters like the `$` end-anchor from the shell); the empty first argument keeps the branch-name default (`git branch --show-current`):

```bash
ISSUE_NUM=$(bash "<skill-dir>/scripts/parse-branch-issue.sh" "" '<branch-issue-pattern>' || true)
```

Leave the script's stderr visible: it carries the deprecation note when the userConfig value is used, and a note naming the source and the reason (never the pattern text) when a layer's section exists but yields no usable pattern (a near-miss heading such as `## branch_issue_pattern:`, no value, a heading or HTML comment as the first value line, an empty or unterminated code fence, or a pattern that is invalid, holds a backreference, or breaks the length, bound, or nested-quantifier limit), which stops resolution with no issue number whatever the lower sources say; when the userConfig value breaks one of those pattern checks and is ignored; or when a match yields no usable reference. Relay any note to the user; stdout carries only the reference. Fill `<branch-issue-pattern>` with the resolved ERE. Its last capture group must resolve to an issue number or a tracker key such as `SW2-1234` (a pattern with no capture group, or a capture of another shape, prints nothing and takes the no-closure path); configure a scheme that captures the reference wherever it sits, e.g. `^[^/]+/([0-9]+)-` for `alice/1234-slug` or `-([0-9]+)$` for `feat/add-widget-1234`.

**Tracker-bound path.** When the `work-items` plugin is installed and the repository has a work-item tracker binding (the `tracker` mapping of `<home>/work-items.yaml`, or the legacy JSON binding at the root), the bound adapter owns the link text (`Closes #42`, `Closes ENG-123`, a Jira key) and the default branch grammar, so this flow writes neither. Parse with `--no-default` as the third positional (pass `''` as the second when no userConfig value is set), so only a consumer `branch_issue_pattern` applies:

```bash
ISSUE_NUM=$(bash "<skill-dir>/scripts/parse-branch-issue.sh" "" '<branch-issue-pattern>' --no-default); PARSE_RC=$?
```

Then invoke `/work-items:track link` via the Skill tool, `<owner>/<repo>` being this PR's repository: on `PARSE_RC` 0, `link --branch-ref "$ISSUE_NUM" --repo <owner>/<repo>`; on `PARSE_RC` 3 (no consumer pattern), `link --current-branch --repo <owner>/<repo>` (add `--worktree "$WT"` under [§2.7](create-pushed.md)), which reads the branch itself and applies the adapter's grammar; never type the branch name into the arguments, since git allows shell metacharacters in it; on `PARSE_RC` 1, no item, so go to the orphan-PR prompt. From the JSON it prints: an item whose `state` is `open` (or `null`, unchecked) sets `CLOSES_LINE` to its `closes` text, or to its `refs` text when `closes` is `null` (a merge closes nothing on that tracker: tell the user to close the item with `/work-items:track done` after the merge); then read that item's body with `/work-items:track view <item_id>`, its `body` becoming `ISSUE_BODY` for §2.4.1's Problem and intent line (empty when the read fails). A `missing` or closed item, or "no linked item", goes to the orphan-PR prompt. Only when the action reports that the adapter predates `change-link` does the GitHub default below run instead. A usage error or a configuration error it reports (a missing branch grammar) stops here: relay it to the user rather than opening a PR with no link. `REFS_LINES` starts empty on this path too. In the multi-issue and orphan-PR prompts below, build each extra line from `/work-items:track link <item>` the same way rather than writing `Closes #X`.

**Without a tracker binding**, the GitHub default
([GitHub](../../../reference/providers/github/pull-request/create.md#closes-line-without-a-tracker))
starts `CLOSES_LINE` and `REFS_LINES` empty. `REFS_LINES` collects newline-separated
`Refs #Y — <why>` bullets for the `## Related` section from the multi-issue or orphan-PR prompts
below; never a closing keyword and not a linkage line (§2.4.1 routes it). When `ISSUE_NUM` is a
number, it validates that the issue exists in the current repository BEFORE shipping `Closes #N`:
GitHub auto-close fires only when the issue exists, lives in this repo, and is open at merge time,
and a typo'd branch like `feat/99999-foo` would otherwise ship a misleading `Closes #99999` line.
An open issue sets `CLOSES_LINE` to `Closes #<N>`; otherwise it warns that the issue is missing or
not open, clears `ISSUE_NUM`, and the orphan-PR prompt below populates `CLOSES_LINE`. The same read
returns the issue's body as `ISSUE_BODY` (empty when the issue is not open), which §2.4.1's Problem
and intent line uses when no plan is found.

**Single-issue branch:** the parser returns `N` from `<type>/<N>-<slug>` (and `chore/routine-issue-<N>-<slug>` for cloud routines). When the issue read confirms the issue exists with state `OPEN`, `${CLOSES_LINE}` becomes `Closes #N`; missing, closed, or otherwise not open falls through to the orphan-PR prompt. Never ship a stale or unverified keyword.

**Sandboxed sessions: run this check over REST.** The CLI's issue read routes through GitHub's GraphQL API, so where the GitHub proxy refuses that read it fails with `HTTP 403` whatever the credentials. The default block swallows that 403 and leaves `ISSUE_STATE` empty, reporting a live, open issue as "missing or not open" and dropping the `Closes #N` line [§2.4.2.1](create-gate.md) gates on. Substitute the REST issue read, which reports `state` in lower case and returns the body as well ([GitHub](../../../reference/providers/github/pull-request/create.md#issue-state-over-rest), with the evidence and its recheck trigger).

**Placeholder anchoring.** A REST call's `{owner}` and `{repo}` placeholders expand from the repository of the **current directory** ([GitHub](../../../reference/providers/github/pull-request/create.md#placeholder-anchoring)). That is safe on the normal `create` path, whose cwd is the branch's own clone, but not under §2.7, where the orchestrator sits out-of-tree: there, run the call from `$WT` (the subshell form §2.7 uses for `resolve-remote.sh`) or name the repository explicitly. The same rule governs the REST PR-create fallback in [§2.4.3](create-open-pr.md).

**Multi-issue PR (same branch closes 2+ issues):** after primary line is set, ask user inline:

> *"This PR closes #N. Any other issues to close on merge? List them one per line (`Closes #X`), use `Refs #Y` to mention an issue without closing it (a `## Related` bullet, not a linkage line), or `no` to skip."*

Append each accepted `Closes #X` line to `${CLOSES_LINE}` (newline-separated); collect each accepted `Refs #Y` line into `${REFS_LINES}`, never onto the closing-keyword line. §2.4.1 routes `${REFS_LINES}` into a `## Related` section (required by resolved config, or ad hoc when non-empty and not required). GitHub accepts one keyword per issue, comma- or newline-separated.

**Branch lacks issue number (orphan PR, such as a drift sweep, hotfix, or refactor):** prompt with these options:

1. `Closes #<N>`: provide a number to auto-close on merge
2. `Refs: #<N>`: reference an issue this PR does not close, on a line of its own
3. `No related issue: <reason>` for an orphan PR, no linkage

`Refs: #N` (or `Relates to: #N`) counts as linkage only with the colon and alone on its line; the exact accepted forms are in the header of [`hooks/pr-linkage-validator.sh`](../../../hooks/pr-linkage-validator.sh). A `Refs #N` without the colon is not linkage at the [§2.4.2](create-gate.md) pre-create gate or in CI, and a `Refs #N — <why>` entry collected into `${REFS_LINES}` (§2.4.1) is a `## Related` bullet, so a PR carrying only those still needs one of the three options above.

When option 2 is chosen, read that issue's body and open sub-issues for §2.4.1's `## Remaining`
section ([GitHub](../../../reference/providers/github/pull-request/create.md#refs-issue-read));
on the tracker-bound path, the `refs` item's `ISSUE_BODY` serves.

Persist chosen line(s) into `${CLOSES_LINE}`. NEVER wrap a closing keyword in an HTML comment: `<!-- Closes #N -->` still parses and auto-closes the issue on merge. Fenced code blocks ARE inert, so example snippets are safe.
