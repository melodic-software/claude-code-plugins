# Resumed context

For each session resumed from a handoff, `resumed` measures its context at the 10th assistant
message after the resume, and groups the sessions by the session-flow plugin version their
transcript names. A change to handoff or resume is judged by comparing the release before it with
the release that carries it, so two changes merged close together stay apart. The script docstring
defines what counts as a resume, a message's context and a session's version.

## Run

```bash
"$PY" "$S/resumed_context.py" --format md [--cwd-prefix '<prefix>' ...] [--since <day>] [--until <day>] \
  [--baseline '<version>' --candidate '<version>'] [--min-per-side <n>]
```

- **One repository.** Pass its root and the path prefix its worktrees share, each as its own
  `--cwd-prefix`; read the worktree location from the repository's AGENTS.md or the worktree
  skill's convention. A merged worktree may be gone, so a session is matched by the path it ran in,
  not by asking git. Without `--cwd-prefix` every project on the machine is read.
- **Comparison.** `--baseline` is the release before the change and `--candidate` the release with
  it. `rise` stays null, and the exit is 1, until both sides hold `--min-per-side` sessions (default
  10); widen the sample with an earlier `--since`. `miss_count` is null: a retro or the owner counts
  the binding rules, decisions and open questions a resumed session missed. Never compare against
  the `unknown` group: it holds sessions whose transcript names no session-flow path.
- **Run time.** It opens every transcript and stops each one early. A run over 3,478 transcripts
  took about 85 s (measured 2026-11-19; recheck when a run exceeds 300 s), so give it a Bash
  timeout of 600000 ms or run it in the background.

## Present

Show the report as it came back. SKILL.md Step 3's rule covers every id, path and version it
prints. The JSON envelope's fields are under "Resumed-context report" in
[../reference/store-layout.md](../reference/store-layout.md).
