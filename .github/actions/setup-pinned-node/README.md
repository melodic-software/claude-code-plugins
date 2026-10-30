# setup-pinned-node

Put the exact Node version a version file pins on `PATH` without a GitHub API call.

`actions/setup-node` reads the `actions/node-versions` manifest through `api.github.com` with the
job token whenever the requested version is not in the runner's tool cache: two requests (the git
tree, then the manifest blob) a step. The runner image caches only the newest `24.*` at its build
date, so the exact `.node-version` pin misses whenever the two differ, and every miss spends the
job token's hourly limit, which every job in the repository shares.

This action uses the tool cache when it holds the version. Otherwise it downloads
`node-v<version>-linux-x64.tar.xz` from `https://nodejs.org/dist`, checks its SHA-256 against
that release's `SHASUMS256.txt`, and extracts it into the tool cache. Both files come from
nodejs.org over TLS, so the check catches a corrupt or truncated download, not a compromised
origin; setup-node's own fallback trusts the same origin with no checksum at all.

## Inputs

| Input | Meaning |
|---|---|
| `node-version-file` | The file holding the exact `X.Y.Z` version, normally `.base/.node-version` |

The step fails on a version that is not `X.Y.Z`, a runner other than Linux X64, a checksum
mismatch, or a `SHASUMS256.txt` without the tarball's line.

## Use

```yaml
- name: Set up Node
  uses: ./.base/.github/actions/setup-pinned-node # zizmor: ignore[self-repository]
  with:
    node-version-file: .base/.node-version
```

A job with a sparse `.base` checkout lists `/.github/actions/setup-pinned-node/` in it. A job whose
root checkout is the code under test, and which already runs that code, uses the root copy, so a
pull request that changes this action is tested by its own CI:

```yaml
- name: Set up Node
  uses: ./.github/actions/setup-pinned-node # zizmor: ignore[self-repository]
  with:
    node-version-file: .node-version
```

Never use the root form in a job that runs with main's trust and has a pull request checked out at
the root: there it would run pull request code. A composite
action in the same checkout runs `install-node.sh` from its sibling directory instead, as
`check-wip-cap` does. Tests: `scripts/setup-pinned-node.test.sh`.
