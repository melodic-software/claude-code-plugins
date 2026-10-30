---
bump: patch
---

### Fixed

- The merge gate's cost hold now holds the infrastructure-as-code files it let through: a `Pulumi.yml` project file and any file under its directory, Terraform's JSON files (`*.tf.json`, `*.tfvars.json`), and ARM templates under the quickstart or Marketplace name (`azuredeploy*.json`, `mainTemplate.json`). A `secrets` reference moved within one workflow stays accepted; the cost tests now also show that one moved into another file holds.
