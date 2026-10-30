---
bump: patch
---

### Fixed

- The cost hold lists `Pulumi.yml`, `*.tf.json`, `*.tfvars.json` and ARM templates under the quickstart names (any `.json` name holding `azuredeploy`) among its infrastructure-as-code paths, and a directory holding `Pulumi.yml` counts as a Pulumi project. The accepted move of a `secrets` reference within one file now gives its reason and what it leaves to the security review, and an ARM template under another name stays with the review lanes. ([#9241](https://github.com/melodic-software/claude-code-plugins/issues/9241))
