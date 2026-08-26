# claude-code-plugins

## Validate a change

Validate with `scripts/affected-tests.sh --run` (add `--explain` to see why each suite was
selected) instead of running every suite; CI still runs everything. A changed file that maps
to zero suites is an error, never "nothing to run". Full contract, including the no-suite
allowlist and the `NOT RUN` ecosystems: [README.md, "Validate a change"](README.md#validate-a-change).

<!-- BEGIN GENERATED: instruction-placement rules index -->

## Conventions that load on demand

Each surface below enters context automatically when Claude reads a file it covers. That trigger
does **not** fire inside subagents, and after a compaction it fires again only when a covered file
is read again. When you are working on something an entry covers and its content is not already in
context, read the file directly.

| Surface | Covers | Topic |
|---|---|---|
| `.claude/rules/catalog-taxonomy.md` | `.claude-plugin/marketplace.json` | Where the marketplace category taxonomy lives; read before adding or changing a plugin's category |

<!-- END GENERATED: instruction-placement rules index -->
