# Changelog

All notable changes to the `engineering-concepts` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.3] - 2026-11-26

### Changed

- Comments outside the necessary posture are removed from this plugin's shared library copies, synced from their canonical sources; no behavior change.

## [0.2.2] - 2026-11-26

### Fixed

- `scripts/lookup.mjs` reports a `--user-config` file that does not exist as "user config file not found: <path>" instead of the bare system code `ENOENT`.

## [0.2.1] - 2026-11-26

### Changed

- Shared library copies synced with comments removed; no behavior change.

## [0.2.0] - 2026-11-26

### Added

- `scripts/adopt.mjs` and the `/engineering-concepts:adopt` skill write adopted standards: the shipped concepts a person or team chooses, each as one line naming the concept, its id and its official source, into `<surface>.md` in the personal layer (`~/.claude/standards/`) or the repository's team standards root, and add that file's row to the layer's index. Without `--yes` the script prints exactly the text it would write: the whole file when new or empty, the appended lines otherwise, and the index row, or the table holding it when the index has none, plus a line saying when a line break will be added to a file or index that lacks one. A new, empty or whitespace-only file's header says how to list its concepts' counterweights: the engineering-concepts lookup with `--counterweights-of` and the ids the file cites. Added lines keep a file's CRLF or LF line endings. A concept already in the file, or in another standards file of the layer or its subfolders (named in the output; symbolic links, `.git` and `node_modules` are not followed, and for the team layer a personal `*.local.md` does not count), is skipped; when the layer has an index, only the files its rows list count, since only those load, and a concept cited only in an unlisted file is adopted with a warning naming that file; an existing row is kept, a file that already cites a concept named but has no row gets one, and a file whose concepts are all cited elsewhere gets none. A replaced file keeps its mode, and a file the person cannot write is refused, never replaced. Errors name files, settings layers, options and file system failures in plain words (your saved plugin options, the repository's settings file, your personal settings file for this repository; could not be read or is not valid; permission denied, it is a folder, not a file, the file system is read-only; an unknown option or one missing its value by name); a plugin settings file that cannot be read or is not valid stops adopt, so its `exclude` and `source_bar` are never ignored, while the lookup only warns; an unreadable index or standards file, a `--user-config` that is not a JSON object, an unknown concept, a concept the `exclude` or `source_bar` setting drops (named with the setting and its layer), a surface file or index that is a symbolic link, a surface named `readme`, an empty `Applies when` text or one holding a backslash, a team root with no standards index, an unreadable `.claude/standards.yaml` or a standards root outside the repository is refused with nothing written. A file past the standards contract's 200-line budget is written with a warning. With no personal index, the file still loads, since the standards folder is then read file by file.
- `lookup.mjs --counterweights-of <id>,<id>` prints one line per counterweight and per conflict of each id, so a stage that loads an adopted standards file reads them from the shipped data instead of a copy in the file.

### Fixed

- `scripts/lookup.mjs` now reports a record whose `owner` is neither an `https://` URL nor a skill name (`plugin:skill`, optionally with a leading `/`) as malformed, with its file and line, and skips it. The records check validates every record with the lookup's own rules (`parseRecord` and `recordLines`, now exported), so the two cannot disagree on which lines are valid or where a bad line is.

## [0.1.0] - 2026-11-26

### Added

- The `engineering-concepts` plugin: shipped software engineering concepts kept as data, one JSONL file per topic under `data/`, each record a pointer to the concept's official source rather than a copied definition. `scripts/lookup.mjs` finds records by id, name or alias (a merged id kept as an alias redirects), filters by topic, concern, kind, stage and reversibility, drops records by id or topic with `--exclude`, applies `--source-bar`, and prints each record as a JSON line with its counterweights and conflicts named. `--check-sources` fetches each official source and marks an unreachable one for re-sourcing without dropping the record. A malformed record is reported on stderr with its file and line while the rest load. The `source_bar` and `exclude` settings resolve through the plugin config cascade (the plugin options, then `docs/conventions/engineering-concepts.yaml` and its `.local.yaml`): the highest valid `source_bar` wins, an invalid one falls back to the default, and every layer's `exclude` list is unioned. The `/engineering-concepts:lookup` and `/engineering-concepts:load` skills drive it. The plugin installs disabled, and no curated records ship in this release.
