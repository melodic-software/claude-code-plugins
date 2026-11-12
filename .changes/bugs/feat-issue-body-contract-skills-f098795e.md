---
bump: minor
---

### Added

- read issue-body skeletons from the org issue-body contract

  track add, decompose, the agent brief and bugs:write now take their
  issue-body headings from the issue-body contract the standards sync
  delivers into each plugin's reference/ directory, the same record the
  org issue forms are generated from. triage checks an issue body against
  the contract with scripts/check-body.mjs, which accepts a field under
  a `##` or `###` heading and treats a form's skipped answer as empty. The tidy
  deferred-item body follows the task type.

- fan the synced issue-body contract into the plugins

  The standards sync delivers the contract once, to
  docs/contracts/issue-body/contract.json. sync-shared-copies.sh now
  copies a JSON canonical byte for byte (JSON has no comment syntax for a
  header) and generates plugins/bugs and plugins/work-items
  reference/issue-body-contract.json from it; the cross-plugin registry
  records the cluster.
