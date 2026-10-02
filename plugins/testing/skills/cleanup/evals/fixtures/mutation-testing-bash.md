# Mutation testing configuration

Fixture config for the cleanup evals' bash-harness case: copied over the fixture's
`.claude/mutation-testing.md` for that case only.

```yaml
tool: manual
command: none, the manual protocol applies each mutant by hand
diff-target: main
mutate:
  - shop/*.sh
operators: default
timeout-ms: 10000
baseline-suite-ms: 100
test-command: bash {tests}
```
