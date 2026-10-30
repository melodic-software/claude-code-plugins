---
bump: minor
---

### Changed

- The cost hold section names the infrastructure-as-code files the merge gate now holds:
  - Pulumi project and stack files in their `.yml` and `.json` forms.
  - `*.tf.json` and `*.tfvars.json`.
  - The ARM template names `azuredeploy.json`, `azuredeploy.*.json`, `*.azuredeploy.json` and `*.azuredeploy.*.json`.
  - Any file under a directory that holds a Pulumi project file.

  It also says why a `secrets` reference moved within one file is accepted: the move adds no
  charge, and where it moved is the review lanes' call.
