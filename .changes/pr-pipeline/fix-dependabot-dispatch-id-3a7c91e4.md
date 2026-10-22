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
- A lanes App commit on a Dependabot pull request must be a version change. The promote step,
  the verdict job's `fix` and `merge` paths, and the pr-merge lane refuse a fix file that is not
  modified in place, not a regular `100644` file (a symbolic link, submodule or executable), or
  whose content changes more than a version: in `package.json` only existing dependency entries'
  plain, bounded semver ranges may change; a lock keeps the Dependabot commit's package keys, and
  each entry resolves to exactly its own `https://registry.npmjs.org/<name>/-/<name>-<version>.tgz`
  with a `sha512-` integrity, the same alias `name` as before, and no install-script change; and requirements lines may add only
  `name==version` pins of projects the fix also unpins, with `--hash=sha256:` continuations. The
  repository's version-bump commit is admitted only when its `plugin.json` changes nothing but
  `version`. The verdict job's `merge` path now checks every commit that
  is not Dependabot's own (matched by account id, web-flow and a valid signature), reads the
  `[ecosystem, directory]` pairs from the base's `.github/dependabot.yml` itself, and requires
  run.json to name the head the model job's gate passed. A refusal escalates the new
  `dependency-fix-refused`.
