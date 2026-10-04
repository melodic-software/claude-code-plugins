# Share a user-scope docs cache across plugins

- Status: accepted
- Date: 2026-10-04

## Context

Issue #6020 adds a cache of upstream documentation pages: fetched bytes, a section map per page,
and the summaries and notes built on those sections. Several plugins fetch the same upstream pages,
and each carries the cache code as a vendored copy of one `lib/` source
([ADR 0019](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md)). A page one plugin
fetched is worth reusing in every other plugin and in later sessions; that reuse is the reason the
cache exists.

The [owner table](../plugin-philosophy.md#configuration-ownership-and-scope) in
`docs/plugin-philosophy.md` puts caches in `${CLAUDE_PLUGIN_DATA}`. That directory does not fit a
cache several plugins share:

- It is per plugin. It resolves to `~/.claude/plugins/data/<id>/`, where `<id>` is derived from the
  plugin identifier, so each plugin would keep its own copy and fetch every page again.
- It is deleted when the plugin is uninstalled from the last place it is installed, unless the
  uninstall passes `--keep-data`. Removing any one plugin would remove the entries the others rely
  on.

Basis: [Plugin manifest reference: Environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables),
as of 2026-10-04.

## Decision

1. **One cache per user, outside any plugin's data directory.** The default location is
   `${XDG_CACHE_HOME:-$HOME/.cache}/claude-docs-cache`. Every plugin that carries the cache code
   reads and writes the same store.
2. **The location is configurable.** The cache directory resolves from, highest first: the
   `--cache-dir` flag, the `DOCS_CACHE_DIR` environment variable, the user-global machine config
   file the cache code reads, then the bundled default above.
3. **The store is bounded.** A size cap, 200 MB by default and configurable, is enforced by
   least-recently-used pruning.
4. **The store is safe to share.** Plugins and sessions may write the same key at once, and the
   copies of the cache code in different plugins may be at different versions. Each entry is an
   immutable directory that a pointer file names, switched by an atomic rename, so a reader never
   sees bytes from two entries. A `store_version` marks the store and each entry, and a reader that
   meets a version it does not know treats the entry as a miss rather than parsing it.
5. **Nothing in the store is committed**, and its contents are untrusted data
   ([untrusted-content](../conventions/untrusted-content/README.md)).

## Alternatives considered

- **`${CLAUDE_PLUGIN_DATA}`, as the owner table says.** Rejected: one store per plugin defeats
  sharing, and uninstalling a plugin deletes entries other plugins still use.
- **A directory under `~/.claude/`.** Rejected: Claude Code owns that directory and its layout, so a
  store there would depend on a layout no plugin controls or documents.
- **A per-session cache.** Rejected: it drops every entry when the session ends, so no later session
  or other plugin reuses a fetched page, which is what the cache is for.

## Consequences

- A page fetched by one plugin is a cache hit for every other plugin and session on the machine.
- Uninstalling a plugin never removes the cache, including uninstalling the last plugin that
  carries it. The size cap bounds what is left; removing it is deleting the directory.
- The cache directory is a new value in the user-global machine config file, alongside the cache's
  other standing values.
- This is an exception to the `${CLAUDE_PLUGIN_DATA}` row of the owner table, which points here.
  Other plugin caches keep that row.

## Switch condition

Move the default location to that directory if Claude Code ships a documented data directory
that plugins share and that survives the uninstall of any one plugin. Recheck when the
[Environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables)
section of the plugin manifest reference adds such a directory or changes when
`${CLAUDE_PLUGIN_DATA}` is deleted.
