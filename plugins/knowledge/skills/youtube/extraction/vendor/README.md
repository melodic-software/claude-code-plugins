# Vendored extraction libraries

`repo-analysis/` and `video-digestion/` are self-contained copies of two shared
Node libraries the youtube extraction pipeline depends on. They are bundled here
because a plugin is cache-isolated — it cannot reference packages outside its own
directory — and installed into `${CLAUDE_PLUGIN_DATA}` at setup via the parent
`package.json`'s `file:./vendor/*` links.

Only runtime source is vendored; each library's own test suite, build config, and
`node_modules` are omitted (the pipeline's tests exercise the integrated behavior).

Both libraries are also consumed by the `course-digest` skill. Until that skill is
retrofitted into this plugin, each carries its own copy. Once both consume the same
bundled source, deduplicate them into a single shared location per the migration
playbook's "Shared code across plugins" decision record (single authoring source,
plain copies at runtime, CI drift gate) rather than maintaining two divergent trees.
