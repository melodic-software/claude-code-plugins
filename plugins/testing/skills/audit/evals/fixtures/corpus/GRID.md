# Corpus coverage grid

One row per adapter in `adapters/`, one column per deterministic rule. A `pair` cell needs a bad
file in `<adapter>/bad/` carrying `expect: <rule>` and a good file in `<adapter>/good/` carrying
`good-for: <rule>`. Any other cell reads `n/a: <reason>`. `scripts/check-corpus-grid.sh` enforces
both.

| Adapter | rule-zero-assertion | rule-recomputed-expectation |
|---|---|---|
| bash-bats | pair | pair |
| bash-harness | pair | pair |
| cs-mstest | pair | pair |
| cs-nunit | pair | pair |
| cs-xunit | pair | pair |
| go-testing | pair | pair |
| js-jest | pair | pair |
| js-node-test | pair | pair |
| js-playwright | pair | pair |
| js-vitest | pair | pair |
| pwsh-pester | pair | pair |
| py-pytest | pair | pair |
| py-unittest | pair | pair |
