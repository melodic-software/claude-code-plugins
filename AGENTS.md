# claude-code-plugins

## Validate a change

Validate with `scripts/affected-tests.sh --run` (add `--explain` to see why each suite was
selected) instead of running every suite; CI still runs everything. A changed file that maps
to zero suites is an error, never "nothing to run". Full contract, including the no-suite
allowlist and the `NOT RUN` ecosystems: [README.md, "Validate a change"](README.md#validate-a-change).
