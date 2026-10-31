# setup-pinned-node

Put the exact Node version a version file pins on `PATH` without a GitHub API call.

`actions/setup-node` reads the `actions/node-versions` manifest through `api.github.com` with the
job token whenever the requested version is not in the runner's tool cache: two requests (the git
tree, then the manifest blob) a step. The runner image caches only the newest `24.*` at its build
date, so the exact `.node-version` pin misses whenever the two differ, and every miss spends the
job token's hourly limit, which every job in the repository shares.

This action uses the tool cache when it holds the version. Otherwise it downloads
`SHASUMS256.txt`, `SHASUMS256.txt.sig` and `node-v<version>-linux-x64.tar.xz` from
`https://nodejs.org/dist` and extracts the tarball into the tool cache only after this chain holds:

1. The trust root is the committed keyring, `pubring.kbx`.
2. `gpgv` verifies `SHASUMS256.txt.sig` against that keyring before anything reads
   `SHASUMS256.txt`.
3. The tarball's SHA-256 matches the signed `SHASUMS256.txt`.

A compromised nodejs.org or CDN that swaps the files fails step 2 unless it also holds a releaser's
signing key; setup-node's own fallback checks nothing at all. A tool-cache hit is the runner image's
own copy and skips the chain.

## Inputs

| Input | Meaning |
|---|---|
| `node-version-file` | The file holding the exact `X.Y.Z` version, normally `.base/.node-version` |

The step fails on a version that is not `X.Y.Z`, a runner other than Linux X64, a signature that
does not verify against the keyring, a checksum mismatch, or a `SHASUMS256.txt` without the
tarball's line.

## Release keyring

`pubring.kbx` holds public keys only. It is a byte-exact copy of `gpg/pubring.kbx` from
[nodejs/release-keys](https://github.com/nodejs/release-keys) at commit
[`481637f813e912c4aa3622d7964ab426c97b8e8d`](https://github.com/nodejs/release-keys/blob/481637f813e912c4aa3622d7964ab426c97b8e8d/gpg/pubring.kbx):
95,960 bytes, sha256 `610b8d249da3d5733f5a128def2dd0294dbbf5b5713e6ca2529db8db419dee00`.

It changes only when Node.js adds or retires a releaser, so a `.node-version` bump needs no edit
here. When the step fails on a signature, check whether the release was signed by a key new
upstream. If so, replace the file from a newer release-keys commit, confirm its fingerprints against
the release-keys README and the [nodejs/node README](https://github.com/nodejs/node#release-keys),
confirm the release's real `SHASUMS256.txt.sig` verifies, and update the commit and sha256 above.
If no new key explains it, treat the download as compromised.

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
`check-wip-cap` does; the script finds the keyring from its own path, so this still works.
Tests: `scripts/setup-pinned-node.test.sh`.
