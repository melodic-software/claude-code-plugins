---
bump: patch
---

### Fixed

- The merge gate's cost hold (`cost-review-required`) now catches the infrastructure-as-code files it let through: a `Pulumi.yml` project file, Terraform's JSON syntax (`*.tf.json`, `*.tfvars.json`) and ARM templates under the quickstart names (any `.json` name holding `azuredeploy`). `pulumi_dirs_at` counts a directory holding `Pulumi.yml` as a Pulumi project, and merge-holds.mjs's `COST_PATHS` copy holds the same paths. A `secrets` reference moved within one file still passes, as before. ([#9241](https://github.com/melodic-software/claude-code-plugins/issues/9241))
