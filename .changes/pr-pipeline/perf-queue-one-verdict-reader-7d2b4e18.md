---
bump: patch
---

### Changed

- In the merge queue, `ci-status` no longer reads a lanes App pull request's pr-verify pass a
  second time. The verdict reader's `--pass-out` file gives the step the counted passes with their
  runs, the first pass's `verdict.json` and the closing issues it judged on, and the step hands
  them to `merge-holds.mjs` `verdictHold` and `linkHold` as before. That drops the four `?name=`
  pass lookups (two of them for digest names the writer never uploads), the run read, the zip
  download with its 5xx retries and the closing-issues GraphQL read. A pass file that does not read
  holds the group. Any reader refusal now reaches `merge-holds.mjs` with no pass, as it already did
  in FAIL index mode. Without the legacy FAILs file, a pass refusal such as
  `verify:untrusted-spec` therefore holds until a trusted approval of the head lifts it.
