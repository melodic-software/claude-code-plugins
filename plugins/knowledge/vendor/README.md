# Vendored extraction libraries

`repo-analysis/`, `video-digestion/` and `node-launcher/` are self-contained Node
libraries the `knowledge` plugin's skills share. They live at the plugin root,
shared plugin-wide, because more than one skill consumes each, and a plugin is
cache-isolated (it cannot reference packages outside its own directory).

- `repo-analysis/` and `video-digestion/` are dependencies of the `video-digest`
  and `course-digest` extraction packages: each skill's
  `skills/<skill>/extraction/package.json` links this single copy through
  `file:../../../vendor/*`, and `setup-deps.mjs` installs it into
  `${CLAUDE_PLUGIN_DATA}` via `npm install --install-links`. `absorb-upstream`
  runs `repo-analysis/clone-cli.js` directly, which needs no install.
- `node-launcher/` is never installed: each extraction package's `run.mjs` and
  `setup-deps.mjs` import it by relative path, and `setup` runs its
  `setup-deps.mjs` with `--package`.

Only runtime source is vendored, each with the `node:test` suite that covers it;
`node_modules` is omitted (the pipelines' tests exercise the integrated behavior).

This is the single authoring source. There is only one committed copy, so there is
nothing to byte-drift. Editing the shared source obligates a plugin `version` bump
(the update cache key), the discipline that replaces the byte-drift gate used for
the multi-copy shared shell lib. See the migration playbook's "Shared code across
plugins" decision record.
