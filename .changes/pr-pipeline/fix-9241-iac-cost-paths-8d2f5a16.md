---
bump: patch
---

### Fixed

- The cost hold's path list now names `Pulumi.yml`, `*.tf.json`, `*.tfvars.json` and ARM templates under the quickstart or Marketplace name (`azuredeploy*.json`, `mainTemplate.json`), and a directory holding a `Pulumi.yml` holds every file under it. The accepted `secrets` move now says why it is net zero: each file is counted on its own, so a reference moved into another file holds.
