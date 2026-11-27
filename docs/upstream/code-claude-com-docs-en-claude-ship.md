# Upstream source: Claude Ship (code.claude.com)

This page records what this repository takes from, adapts, already has, or rejects in the
[Claude Ship](https://code.claude.com/docs/en/claude-ship) docs page (Anthropic product
documentation; no license grant found). Rows hold our decisions and our own descriptions of each
idea, under the upstream-drift convention's
[What a row may describe](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/upstream-drift/README.md#what-a-row-may-describe);
read upstream at each row's link for what it says. Verdicts for overlapping built-in commands
(`/ship`, `/steward`, the `ship:review` alias) live in the
[native-surfaces store](../native-surfaces.md), ruled by
[ADR 0137](../adr/0137-rule-native-surface-overlaps-by-five-ordered-tests.md).

- **Pointer**: when a consumer reports a plan that includes the Claude Ship agents, or the page
  changes which plans or billing the agents use, fetch
  <https://code.claude.com/docs/en/claude-ship#plans-and-billing> live and re-rule each row.

## Attribution table

**Stated**: the upstream gives this problem where the label's link points. **Inference**: we
derived it from the mechanism. Disposition is `take`, `adapt`, `already have` or `reject`, with the
reason.

| Idea (link at the pin) | What it does | Upstream problem, motivation, goal | Our problem | Disposition |
|---|---|---|---|---|
| [Code Review](https://code.claude.com/docs/en/claude-ship#code-review-finds-problems) | An organization-level agent reads each pull request with its surrounding code and posts severity-ranked inline findings. | Teams want defects caught on the pull request before a person reviews it. **Inference** | Review findings on every pull request: plugins/review/skills/code-review and plugins/review/skills/security-review run as CI lanes. | **already have:** our CI review lanes. The agent is for Team and Enterprise organizations and bills usage credits per run (ADR 0137 tests 3 and 4), so it stays docs-only until a consumer's plan includes it. |
| [PR Steward](https://code.claude.com/docs/en/claude-ship#pr-steward-pushes-fixes) | An organization-level agent pushes commits that address failing checks, conflicts and review comments, and is built never to approve or merge. | Moving a pull request from feedback to green takes repeated manual rounds. **Inference** | Driving open pull requests to green: plugins/source-control/skills/babysit-prs and plugins/source-control/skills/babysit-loop. | **already have:** the babysit skills. Same plan and billing limits as Code Review, so docs-only. The local `/steward` command is ruled in the store after the trial ([#19407](https://github.com/melodic-software/claude-code-plugins/issues/19407)). |
| [Claude Approvals](https://code.claude.com/docs/en/claude-ship#claude-approvals-applies-your-policy) | A check reads a policy file in the repository and reports which approvals a change still needs; it blocks merges only where branch rules make it required. | Teams want approval rules expressed per path and enforced by a check. **Inference** | Deciding when a pull request may merge: the `CI Status` check and plugins/source-control/skills/pull-request/reference/merge.md, with plugins/review/skills/merge-risk rating risk. | **already have:** our merge gate and risk rating. Plan-limited and billed per classifier run, so docs-only. |
| [The bundled claude-approvals skill](https://code.claude.com/docs/en/approvals) | Claude Code ships a skill that guides editing an Approvals policy file and its classifiers. | Policy edits that look harmless can let changes merge unreviewed. **Inference** | none: this repository keeps no Approvals policy file. | **reject:** nothing here uses Claude Approvals; revisit with the Claude Approvals row. |
| [Plans and billing](https://code.claude.com/docs/en/claude-ship#plans-and-billing) | The agents run only for Team and Enterprise organizations and bill token usage through usage credits, outside the plan's included usage. | Separating agent spend from seat usage. **Inference** | Which consumers can reach a surface, and what bills them: ADR 0137 tests 3 and 4. | **already have:** ADR 0137 rules plan-limited and billed surfaces by the consumer's own plan and cost choice. |
| [Turn off Claude Ship](https://code.claude.com/docs/en/claude-ship#turn-off-claude-ship) | Turning the agents off is ordered so a policy cannot start billed reviews, and it leaves the local commands on. | Stopping charges without a gap. **Inference** | none: no agent is on here. | **reject:** nothing to turn off. |

The desktop Claude Ship surface is not described on this page; it is recorded with the store's
desktop question.

## License notice

The page carries no license grant; it is Anthropic product documentation. No upstream text is
copied: every cell is our own description, and the page is linked by section.

- **Pointer**: <https://code.claude.com/docs/en/claude-ship> (no license section found)
- **As of**: 2026-11-27
- **Recheck trigger**: the page adds a license or terms section, or its plans and billing section changes
