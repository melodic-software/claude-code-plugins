# Vendored extraction libraries

`repo-analysis/` and `video-digestion/` are self-contained copies of two shared
Node libraries the course-digest extraction pipeline depends on. They are bundled
here because a plugin is cache-isolated — it cannot reference packages outside its
own directory — and installed into `${CLAUDE_PLUGIN_DATA}` at setup via the parent
`package.json`'s `file:./vendor/*` links.

Only runtime source is vendored; each library's own test suite, build config, and
`node_modules` are omitted (the pipeline's tests exercise the integrated behavior).
`video-digestion` declares a runtime `imghash` dependency, installed transitively at
setup.

Both libraries are also vendored by the sibling `youtube` skill. Each carries its own
copy for now; once both consume the same bundled source, deduplicate them into a single
shared location per the migration playbook's "Shared code across plugins" decision record
(single authoring source, plain copies at runtime, CI drift gate) rather than maintaining
two divergent trees.
