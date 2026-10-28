---
bump: minor
---

### Changed

- The pr-merge gate lets a pull request a person on the trusted-actor list opened clear a `gate` floor path that only their own commits touched on a clean security review of a head pr-verify passed, as an `enforcement` path clears; lanes App and bot pull requests, a lane fix on a gate path and every `trust` path still wait for a person; `.github/actions/resolve-config/**` and `docs/conventions/pr-pipeline.yaml`, which scope lane tokens, are now `trust`, so it never takes the lift.
