---
bump: major
---

### Removed

- The one-release reads of the old team locations, added in 0.13.0. `resolve-roles.sh`, and so `/multi-agent:route`, reads the team layer only from `docs/conventions/multi-agent.yaml` (under the convention home the repository binds), never from the config block in `docs/conventions/multi-agent.md` or from `.claude/multi-agent.yaml`. `/multi-agent:setup check` prints a `WARN team:` row for each old file it finds, with its next step. While the YAML is absent, the first `/multi-agent:setup apply --layer team` write still copies one old file's keys into it, the block's when there is one, and leaves that file in place. A repository that keeps its role map in an old file runs that write, then deletes the old file ([#9737](https://github.com/melodic-software/claude-code-plugins/issues/9737)).
