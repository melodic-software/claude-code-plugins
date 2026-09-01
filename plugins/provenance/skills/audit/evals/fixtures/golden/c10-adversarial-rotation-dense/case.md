# What the runner does with a failed job

If a job breaks, Widget Runner checks the retry rule attached to that job before it determines
whether to queue the job afresh. The rule names an approach, a cap on attempts, plus an optional
wobble fraction. A job with no rule of its own adopts the workspace baseline, which retries two
times with linear back-off and no wobble. The runner logs every attempt on its own line within
the log, so a job that in the end succeeds nonetheless shows its failures.
