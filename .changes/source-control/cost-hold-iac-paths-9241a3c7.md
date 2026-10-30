---
bump: patch
---

### Changed

- The `cost-review-required` hold now covers more infrastructure-as-code files:
  - Pulumi project and stack files in their `.yml` and `.json` forms (`Pulumi.yml`, `Pulumi.json`,
    `Pulumi.*.yml`, `Pulumi.*.json`).
  - Terraform's JSON files (`*.tf.json`, `*.tfvars.json`).
  - The ARM template names `azuredeploy.json`, `azuredeploy.*.json`, `*.azuredeploy.json` and `*.azuredeploy.*.json`.

  A directory holding any Pulumi project file at the base now counts as a Pulumi project, and
  `merge-holds.mjs` carries the same paths. A `secrets` reference moved within one file still
  passes, because it adds no charge.
