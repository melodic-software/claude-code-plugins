# Mutation testing configuration

Fixture config for the gated cleanup eval over `cleanup-dotnet`, with the keys
`/mutation-testing:setup apply` writes and the `test-command` it proposes for a `dotnet test`
runner. `tool: manual` keeps the eval free of a Stryker.NET install; cleanup's record and replay
run the manual protocol with `test-command` whatever the tool.

```yaml
tool: manual
command: none, the manual protocol applies each mutant by hand
diff-target: main
mutate:
  - Shop/*.cs
operators: default
timeout-ms: 120000
baseline-suite-ms: 15000
test-command: dotnet test {tests}
```
