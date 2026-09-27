# Retry policy

When a task fails, Widget Runner checks the retry policy attached to that task before it
determines whether to schedule the task again. The policy specifies a strategy, a ceiling on
attempts, and a discretionary jitter fraction. A task with no policy of its own adopts the
workspace default, which reattempts twice with linear backoff and no jitter. The runner writes
every attempt individually in the log, so a task that ultimately succeeds still shows its
failures.
