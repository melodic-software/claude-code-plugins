---
bump: minor
---

### Added

- **`/testing:cleanup` offers cannot-fail-only mode when the mutation run cannot gate the folder** ([#11005](https://github.com/melodic-software/claude-code-plugins/issues/11005)). Step 3 used to stop the batch when `/mutation-testing:audit` recorded `K0 empty` or ended as `no mapping: scope empty`. A suite that reaches its code through dependency injection or an interface, common in .NET, maps nothing. Cleanup now names the result and offers cannot-fail-only mode, continuing only on your yes. It does the same when the audit refuses because you declined both its install command and `tool: manual`. Any step 2 quarantines stay in the batch, and a batch with no cannot-fail candidate still reports them. Unattended, it still stops. A new `cannot_fail_only_offered_on_empty_mapping` eval covers the offer on the `cleanup-dotnet` fixture.
