# Source Control Convention

How work on an open pull request in this repository is handled after the PR exists. The source-control
plugin's settings live in [`source-control.yaml`](source-control.yaml) and
[`.claude/source-control.md`](../../.claude/source-control.md); this file holds prose rules that any
session working a PR reads, including a cloud session that does not load the plugin.

## Post-PR triage

These rules apply to every session that responds to CI results or review comments on a pull request
here: `/source-control:pull-request` `monitor`, `/source-control:babysit-prs`, and a cloud session
started with the built-in `/autofix-pr` command. The full procedure, with its per-finding
verification steps, is
[`plugins/source-control/reference/review-discipline.md`](../../plugins/source-control/reference/review-discipline.md).

- **Doubt bot findings until the code confirms them.** A review bot's comment is a claim about the
  code. Read the referenced lines on the PR head and check the claim before changing anything. A
  finding the code does not bear out gets a reply with the evidence, not a fix.
- **Change only what a confirmed finding needs.** Do not rework code a finding did not touch, restyle
  passing code, or reopen a decision a person already settled on the thread. Each extra push restarts
  CI and the review bots and can raise new findings about the extra change.
- **Hand unclear cases to a person.** When the evidence does not settle a finding, or the fix would
  change scope, a public interface, or a security property, say so on the thread, leave it
  unresolved, and report it. Do not guess.
- **A failing check gets one rerun per head.** If it fails again on the same commit, treat the failure
  as real: fix it or report it.
- **`/autofix-pr` sessions do not merge.** They fix and push only: never merge, arm auto-merge, or
  add the PR to a merge queue. Merging is decided outside that session, under the merge rules in
  [`AGENTS.md`](../../AGENTS.md).
