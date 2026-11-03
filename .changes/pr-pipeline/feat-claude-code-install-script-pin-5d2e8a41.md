---
bump: minor
---

### Added

- review-dependency moves the `@anthropic-ai/claude-code` install-script approval (`allowScripts`
  in `package.json`) to the version `package-lock.json` installs, inside the Dependabot pull
  request, with no model turn: `review-dependency-select` writes the one-line patch
  (`install-script-pin.mjs`), and the new `apply-dependency-pin` job pushes it with
  `apply-dependency-patch`'s existing grant under the new `install-script-pin` patch row. The
  row admits the root `package.json` alone with that one pin renamed to the exact version the
  manifest pins; a name-only or wildcard key, another package's pin or any other change is
  refused. The pin round posts no round marker; the new head is reviewed as any other, and the
  select step writes the from and to versions to its step summary.
- `check-catalog` fails `ci-status` while the pin and the lockfile disagree, so a Dependabot bump
  of the CLI sorts `review` and reaches the pin step.
- The fix rule (`fixRefusal`) admits that pin move in a lanes App fix commit, so the pr-merge
  lane can merge the reviewed pull request.
