## 31. Scheduled Runs

Schedule a task to run overnight.

```
widget cron "0 2 * * *" nightly-rebuild
```

Uses: PR babysitting, Slack summaries, deploy monitoring, any repeating workflow.

Learn more: https://example.invalid/widget-runner/docs/schedules

## 32. Review: Agents Hunt for Flaky Tests

When a PR opens, Widget Runner dispatches a team of agents to hunt flaky tests. The Widget team built it for themselves first. Task output was up 200% this year, and triage was the bottleneck.

Each agent focuses on one concern, such as timing races, shared state, or network calls, then posts inline comments on the PR. The maintainers used it for weeks before launch; it catches real flakes they would have missed.

Source: https://example.invalid/posts/5120

## 33. Our rollout

We turned it on for the `fast` pool first, and only after the agents' comments stopped duplicating
each other.
