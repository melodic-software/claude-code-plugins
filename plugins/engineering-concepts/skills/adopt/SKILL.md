---
description: "Adopts chosen shipped engineering concepts into a personal or team standards file: each concept as a line with its id and official source, its counterweights and conflicts under it, and the file's index row, written only after an explicit yes. Use when asked to adopt a concept or a topic's concepts as a standard, or to make them load in every design, plan and review. Not for a one-off question: /engineering-concepts:lookup; not for this session only: /engineering-concepts:load."
argument-hint: "<topic|concept...> [personal|team]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Write chosen shipped concepts into a personal or team standards file
---

# Adopt

Turn shipped concepts into adopted standards: the person or team chooses entries, and each one is
written into a standards file that the standards loader already reads at design, plan and review
time. The shipped concepts hold no positions; adopting is the step that takes one.

1. **Show the entries.** Run the lookup for the topic (or the named concepts) and list each entry
   as its name, id, official source, stage, and counterweights and conflicts by name. Keep the
   heredoc as written: it hands the plugin's saved options to the script
   ([Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)).

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/lookup.mjs" --topic <topic> --project "<repository root>" --user-config - <<'EC_SETTINGS'
   source_bar=${user_config.source_bar}
   exclude=${user_config.exclude}
   EC_SETTINGS
   ```

   Exit 1 with a stderr line `"event":"catalog empty"` means no shipped concepts exist yet: say so
   and stop. Exit 1 otherwise means nothing matched: name what was tried and stop.

2. **Ask** which entries to adopt (never pre-select), and where:
   - `personal`: `~/.claude/standards/`, the person's own standards in every repository.
   - `team`: the repository's standards root, committed and shared; it needs the repository's
     standards index to exist already.

   Also settle the surface name, a kebab-case file name (recommend the topic), and an
   `Applies when` sentence for the index row naming the tasks and files the concepts bear on. The
   [standards contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/standards/README.md#layers-and-precedence)
   says how the layers combine: a team standard wins a direct clash with a personal one.

3. **Preview.** Run the adopt script without `--yes`; exit 3 prints exactly what it would add to
   the file and the index. Show that output to the person unchanged.

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/adopt.mjs" <id>... --layer <personal|team> --surface <name> --applies-when "<clues>" --project "<repository root>"
   ```

4. **Write on an explicit yes** by re-running the same command with `--yes`. On anything else,
   stop with nothing written. If either run is refused, report the refusal and stop; never reshape
   the command and retry.

5. **Report** the file and index written. For `team`, the files are new or changed in the working
   tree until committed: say so.

Exit codes and stderr events (JSON lines):

- 0 with "already adopted": every entry is in the file and the row exists; nothing written.
- 1 `concept not found`: name the term; nothing written.
- 1 `no team index`: the repository has no standards index; offer the repository's standards setup
  instead of writing one here.
- 1 `standards config unreadable` or `standards root outside the repository`: report the file
  named; nothing written.
- 2 `invalid option`: fix the named option and run the preview again.

## What this skill does not do

- It writes no `*.local.md` personal override: those are never indexed, and one replaces the team
  file of the same name.
- It creates no team index and edits no other index row.

## Related

- One question about a concept, nothing written: /engineering-concepts:lookup.
- Concepts kept in view for this session only: /engineering-concepts:load.

## Next

`/planning:design`, where the adopted standards load with the layer's other standards.

## Gotchas

- An entry already in the file is skipped and an existing row is kept, so re-running is safe; it
  never edits a row's `Applies when`.
- The counterweight and conflict lines are the point: a consuming stage reads them beside the
  entry, so a concept is never applied without what pulls against it. Never strip them.
- With no personal index, the file still loads, by glob discovery of `~/.claude/standards/`.
