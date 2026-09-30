# Widget Runner: compiled tips

Synthetic source page for the attribution golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/tips/compiled`.

## 77. Watch Mode

Source: https://example.invalid/posts/4471

```
widget watch --until "all targets green"
```

**How it works:** the retry loop, built into Widget Runner. Each exit attempt is intercepted; the runner re-checks your condition before stopping. The loop only ends when the condition is met.

**Companion tools (already in this skill):**

- `widget every` (tip 31, 48): runs a task on repeat. Good for iterative cleanups, burning down a backlog.
- `widget cron` (tip 43, 48): starts a task on a cadence. Nightly rebuilds, morning triage, weekly cleanup.
- `on-exit` hook (tip 7, 13, 24): programmatic control over when a run can finish. Run your test suite, hit a CI endpoint, gate on anything.
- Unattended mode (tip 42, 68): lets the runner work without approval prompts.

**Pairs with Tip 76 (Fleet View):** fleet view runs many sessions at once; watch mode makes each finish what it started.
