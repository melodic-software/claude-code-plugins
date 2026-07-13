# Vendored extraction libraries

`repo-analysis/` and `video-digestion/` are self-contained copies of two shared
Node libraries the `knowledge` plugin's extraction pipelines depend on. They live
at the plugin root — shared plugin-wide — because both the `youtube` and
`course-digest` skills consume them, and a plugin is cache-isolated (it cannot
reference packages outside its own directory). Each skill's
`skills/<skill>/extraction/package.json` links this single copy through
`file:../../../vendor/*`, and `setup-deps.mjs` installs it into
`${CLAUDE_PLUGIN_DATA}` via `npm install --install-links`.

Only runtime source is vendored; each library's own test suite, build config, and
`node_modules` are omitted (the pipelines' tests exercise the integrated behavior).

This is the single authoring source — there is only one committed copy, so there is
nothing to byte-drift. Editing the shared source obligates a plugin `version` bump
(the update cache key), the discipline that replaces the byte-drift gate used for
the multi-copy shared shell lib. See the migration playbook's "Shared code across
plugins" decision record.
