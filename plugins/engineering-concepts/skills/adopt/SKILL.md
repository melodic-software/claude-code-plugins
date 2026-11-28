---
description: "Adopt chosen shipped engineering concepts (id, official source, index row) into a personal or team standards file, written only after an explicit yes. Use when: 'adopt a concept as a standard', 'make concepts load in every review'. Not for one-off queries: /engineering-concepts:lookup; not for this session: /engineering-concepts:load."
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
   lines from `<<'EC_SETTINGS'` to the closing `EC_SETTINGS` as written, here and in step 3: they
   hand the plugin's saved options to the script
   ([Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)).

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/lookup.mjs" --topic <topic> --project "<repository root>" --user-config - <<'EC_SETTINGS'
   source_bar=${user_config.source_bar}
   exclude=${user_config.exclude}
   EC_SETTINGS
   ```

   Exit 1 with an error-output line `"event":"catalog empty"` means no shipped concepts exist yet:
   say so and stop. Exit 1 otherwise means nothing matched: name what was tried and stop.

2. **Ask** which entries to adopt (never pre-select), and where:
   - `personal`: `~/.claude/standards/`, the person's own standards in every repository.
   - `team`: the repository's standards root, committed and shared; it needs the repository's
     standards index to exist already.

   Also settle the surface name, a short lowercase name with dashes that becomes the file name
   (recommend the topic), and an `Applies when` sentence for the index row naming the tasks and
   files the concepts bear on. The
   [standards contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/standards/README.md#layers-and-precedence)
   says how the layers combine: a team standard wins a direct clash with a personal one.

3. **Show the file text.** Run the adopt script without `--yes`; exit 3 prints exactly the text
   the write adds: the whole file, heading included, when it is new or empty, the appended lines
   when it has text, and the index row, or the table holding it when the index has none. When the
   file or the index does not end with a line break, a line says one will be added. Show that
   output to the person unchanged.

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/adopt.mjs" <id>... --layer <personal|team> --surface <name> --applies-when "<clues>" --project "<repository root>" --user-config - <<'EC_SETTINGS'
   source_bar=${user_config.source_bar}
   exclude=${user_config.exclude}
   EC_SETTINGS
   ```

4. **Write on an explicit yes** by re-running the same command with `--yes`. On anything else,
   stop with nothing written. If either run is refused, report the refusal and stop; never reshape
   the command and retry.

5. **Verify.** Read the written file and the index back, and confirm each adopted entry line and
   the file's row are there as previewed. Report what you read, not what the script said. For
   `team`, also run on each written file, from the repository root:
   - `git check-ignore -v <file>` reports no match. A match means git ignores the standards folder
     or the file: report the pattern and the file it comes from, since the team never sees an
     ignored standard.
   - `git ls-files --error-unmatch <file>` exits 0. Non-zero right after a fresh write means
     written but untracked: commit it to share with the team, never success.

6. **Report** the file and index written. For `team`, the files are new or changed in the working
   tree until committed: say so.

Exit codes and error-output events (one JSON record per line):

- 0 with "already adopted": every concept is in the file, or in another standards file of the
  layer that the output names; nothing written. When the file itself cites a concept named but the
  index has no row for it, the row is added (the preview shows it); when every concept is cited
  only in other files, no row is added.
- 1 `concept not found`: name the term; nothing written.
- 1 `concept excluded`: the `exclude` or `source_bar` setting named in `setting` drops the concept,
  as the lookup does; report the `reason`, which names the layer, and the `path` of its file when
  it has one; nothing written. Changing the setting is the person's call.
- 1 `symbolic link refused`: the surface file or index at `path` is a symbolic link; report it and
  leave the file it points to for the person to edit; nothing written.
- 1 `no team index`: the repository has no standards index; offer the repository's standards setup
  instead of writing one here.
- 1 `standards config unreadable` or `standards root outside the repository`: report the file
  named; nothing written.
- 1 `settings file unreadable` or `settings file invalid`: the plugin settings file at `path`
  could not be read, or was read but is not valid, so its `exclude` and `source_bar` cannot be
  honored; report the `reason` and stop until it is fixed. The lookup only warns about the same
  file.
- 1 `file unreadable`: the index, the surface file or another standards file of the layer at
  `path` could not be read (the `reason` says why, such as a folder in its place); nothing written.
- 1 `write refused` or `write failed`: report the `message`, which names the file and why (no
  write permission for the file, a read-only file system); `code` keeps the system code. A refusal
  comes before anything is written, in the preview too; a file is never replaced without write
  permission for it.
- 2 `invalid option`: fix the named option (its `reason` says what is wrong) and run the preview
  again.
- A `cited in a file the index does not list` warning: the file at `path` cites the concept but
  the index has no row for it, so it does not load, and the concept was adopted into the surface
  file. Report the `reason`; listing that file in the index or removing its entry is the person's
  call.
- A `standards file over budget` warning: the file passed the contract's soft budget of roughly
  200 lines; the write still happened. Offer to split it by concern into a new surface.

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
  never edits a row's `Applies when`. A concept another standards file of the layer already cites,
  subfolders included, is skipped too, and the output names that file: report it rather than
  moving the entry. A symbolic link, `.git` or `node_modules` inside the layer is not followed.
  For `team`, a concept cited only in a personal `*.local.md` file is still adopted, since that
  file is personal. When the layer has an index, only the files its rows list count, since only
  those load.
- The file holds no counterweight or conflict lines, so they never go stale against the shipped
  data. A consuming stage that loads an adopted standards file runs the lookup on the ids the file
  cites and keeps one line per counterweight or conflict beside each entry:
  `node "${CLAUDE_PLUGIN_ROOT}/scripts/lookup.mjs" --counterweights-of <id>,<id>`.
- With no personal index, the file still loads: the standards folder is read file by file.
- A backslash in `Applies when` is refused; a `|` needs no escaping.
