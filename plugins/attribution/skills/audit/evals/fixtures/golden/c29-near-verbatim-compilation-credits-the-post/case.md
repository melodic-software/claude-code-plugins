# Autonomy: letting the runner drive itself

## Watch mode

The runner's maintainers announced watch mode in a post (<https://example.invalid/posts/4471>),
and the example below is theirs.

```
widget watch --until "all targets green"
```

**How it works:** the retry loop, built into Widget Runner. Each exit attempt is intercepted; runner re-checks your condition before stopping. Loop only ends when condition is met.

**Companion tools (already in this skill):**

- `widget every` (tip 31, 48): runs a task on repeat. Good for iterative cleanups, burning down a backlog.
- `widget cron` (tip 43, 48): starts a task on a cadence. Nightly rebuilds, morning triage, weekly cleanup.
- `on-exit` hook (tip 7, 13, 24): programmatic control over when a run can finish. Run your test suite, hit a CI endpoint, gate on anything.
- Unattended mode (tip 42, 68): lets the runner work without approval prompts.

## Where we use it

Nightly rebuilds of the `heavy` pool, and nowhere else so far.
