---
bump: patch
---

### Changed

- The install guidance points at the [kjanat/actionlint](https://github.com/kjanat/actionlint) fork's v1.17.0 install guide, the release melodic-software CI pins ([ci-workflows#788](https://github.com/melodic-software/ci-workflows/issues/788)). That covers the missing-actionlint notice from `prerequisites.json`, the git pre-commit entry's install command (`brew install --cask kjanat/tap/actionlint`), the README Requirements section and `/actionlint:setup apply`. The fork accepts `$/` refs and `concurrency.queue`, which rhysd/actionlint 1.7.12 rejects; the unqualified `actionlint` package in Homebrew core and most registries still installs upstream.
