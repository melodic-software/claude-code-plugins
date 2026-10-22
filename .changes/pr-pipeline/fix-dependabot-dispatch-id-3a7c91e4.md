---
bump: patch
---

### Fixed

- review-dependency dispatches again. dependency-dispatch matched Dependabot by the login
  `dependabot[bot]`, but the GraphQL listing names the Bot `dependabot`, so every Dependabot pull
  request was dropped and no dependency review ever ran. It now matches the Bot account id
  (49699333).
- A review-dependency `fix` lands only when its commits change npm (`package.json`,
  `package-lock.json`, `npm-shrinkwrap.json`) or pip (`requirements*.txt`/`.in`) manifest and lock
  files outside `.github/`, in a directory `.github/dependabot.yml` lists for that ecosystem. The
  promote step checks every changed path against the base's `dependency-classify.mjs` (copied
  with its SHA-256 before any model turn) and leaves any other fix
  off the branch, which the verdict job escalates as `dependency-fix-not-landed`; the verdict
  job checks the same rule on what landed, and the `dependency-review` patch row allows only the
  new `dependency-manifests` predicate.
- A `merge` verdict on a Dependabot pull request that changes a workflow or action file posts no
  merge marker and escalates the new `dependency-workflow-held`, so a person merges it.
