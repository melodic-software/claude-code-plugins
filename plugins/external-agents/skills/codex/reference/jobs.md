# Jobs: status, result, cancel

Every run and review writes one job file when Codex starts and updates it when Codex ends. Jobs
are grouped per repository (all worktrees of one repository share a group; outside a repository,
one `no-repo` group), and the command lists, reads and cancels only the current directory's
group. The newest `jobs.keep` finished jobs per group are kept.

```bash
external-agents status            # every job in this repository, newest first
external-agents status <job>      # one job: status line, then id, use, mode, times, exit code, thread_id, CLI version, paths
external-agents result <job>      # status line, then Codex's final message
external-agents cancel <job>      # stop a running job and its process tree
```

- **`status`** settles stale jobs: a `running` job whose process is gone is rewritten
  `failed (process exited)`. Use `status <job>` for the `mode:` the reply's first line needs and
  the `thread_id` a resume needs.
- **`result`** exits like the run did (`0`, `1` or `3`), and `1` while the job is still running;
  report a running job as running, not as failed.
- **`cancel`** refuses when the job is not running, or when it cannot confirm the recorded pid is
  still that job's process; nothing is killed then. A cancelled job is recorded `cancelled`.
- **Paths.** `status <job>` prints `log_path` (Codex's full event stream) and
  `final_message_path`. Read the final message; open the event log only to explain a failure or a
  blocked command, and quote only the lines that matter. Job files can hold prompts and output:
  never copy them out of the plugin's data directory, into a commit, an issue or a pull request.
