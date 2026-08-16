# AGENTS.md

## Synced standards are overwritten, not edited here

This repository's lint, formatting, and repository-hygiene configuration is
synchronized from `melodic-software/standards`. Any file that standards marks
as `managed` for this repository — including this file — is replaced on the
next sync, so a local edit to such a file is silently lost. When one of them
is wrong, fix the cause upstream in `melodic-software/standards` and let the
sync carry the correction back — never patch the materialized copy here.

To opt this repository out of a managed component, or to customize its copy,
propose a `melodic-software/standards` pull request moving the component from
`managed` to `locally-owned` for this repository in
`distribution/sync-manifest.yml`. The synchronizer never reads, changes, or
deletes a `locally-owned` file, so after that change lands this repository may
edit or delete its copy in an ordinary local pull request.

## Cloud sessions and plugins

- `.claude/settings.json` is this repository's plugin source of truth: cloud
  sessions install exactly the marketplaces and `enabledPlugins` it declares —
  a repo that declares nothing gets nothing.
- `.claude/cloud-bootstrap.sh` is owned by the standards
  `components/cloud-bootstrap` component — its README is the contract, and
  the sync manifest records whether this repository takes it `managed` or
  owns it `locally-owned`. Repo-specific setup goes in
  `.claude/cloud-bootstrap.local.sh` (committed, never synced), never in an
  edit to a managed copy.
