# Mutation testing configuration

Fixture config for the exercised-scope evals and live runs.

```yaml
tool: manual
command: none, the manual protocol applies each mutant by hand
diff-target: main
mutate:
  - app.py
operators: default
timeout-ms: 10000
baseline-suite-ms: 200
test-command: python -m unittest {tests}
```
