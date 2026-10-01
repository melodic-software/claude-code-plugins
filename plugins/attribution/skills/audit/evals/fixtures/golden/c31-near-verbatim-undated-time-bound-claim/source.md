# Widget Runner: compiled tips

Synthetic source page for the attribution golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/tips/compiled`.

## 31. Scheduled Runs

Run a task on a timer without a terminal open.

```
widget cron "0 2 * * *" nightly-rebuild
```

Uses: PR babysitting, Slack summaries, deploy monitoring, any repeating workflow.

Learn more: https://example.invalid/widget-runner/docs/schedules

## 32. Review: Agents Hunt for Flaky Tests

When a PR opens, Widget Runner dispatches a team of agents to hunt flaky tests. The Widget team built it for themselves first. Their task output was up 200% this year, and triage was the bottleneck.

Each agent focuses on one concern, such as timing races, shared state, or network calls, then posts inline comments on the PR. The maintainers used it for weeks before launch, and it catches real flakes they would have missed.

Source: https://example.invalid/posts/5120
