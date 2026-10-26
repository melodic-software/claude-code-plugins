---
bump: patch
---

### Fixed

- **resolve-conflicts:** a new second discipline, ahead of the Task, tells the agent to decline a bulk side-pick even when the user asks for it. It names the commands to leave unrun (`git checkout --ours/--theirs`, `git restore --ours/--theirs`, `-X ours/theirs`, `--strategy-option ours/theirs`, `-s ours`, and any command that writes one side's or one ref's version over a conflicted path) and what to do instead: list the unmerged paths, recover each side's intent, then resolve each file or stop and ask. When a file's evidence says one side wins, the agent writes that side by editing the file. Before this, the refusal was only a definition inside the first discipline, and aborting was the only shortcut with a stated alternative.
