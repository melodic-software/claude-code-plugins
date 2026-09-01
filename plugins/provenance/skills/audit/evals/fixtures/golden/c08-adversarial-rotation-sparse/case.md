# Retry behavior in our builds

When a task fails, Widget Runner checks the retry policy attached to that task before it decides
whether to schedule the task again. The policy names a strategy, a cap on attempts, and an
optional jitter fraction. A task with no policy of its own takes on the workspace default, which
retries twice with linear backoff and no jitter. The runner records every attempt individually in
the log, so a task that eventually succeeds still shows its failures.

We leave the default in place on every task except the two integration suites.
