# Mutation testing configuration

Fixture config for the cleanup evals.

```yaml
tool: manual
command: none, the manual protocol applies each mutant by hand
diff-target: main
mutate:
  - shop/*.py
operators: default
timeout-ms: 10000
baseline-suite-ms: 300
test-command: python -m unittest {tests}
```
