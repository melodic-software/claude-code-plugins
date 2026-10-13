#!/usr/bin/env bash
# The lane's runner merged main into the PR head with --no-commit; scripts/package.sh conflicts
# (main renamed build_bundle to make_bundle, the PR added --compress to build_bundle). The PR also
# added a release.yml step that calls build_bundle, which merged cleanly and is now stale.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p scripts .github/workflows
cat > scripts/package.sh <<'SH'
#!/usr/bin/env bash
# Sourced by the release workflow.

build_bundle() {
  tar -cf dist/bundle.tar src
}
SH
cat > .github/workflows/release.yml <<'YML'
name: release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
YML
git add .
git commit -q -m "ci: release workflow"

git checkout -q -b feature/compress
cat > scripts/package.sh <<'SH'
#!/usr/bin/env bash
# Sourced by the release workflow.

build_bundle() {
  if [ "${1:-}" = "--compress" ]; then
    tar -czf dist/bundle.tar.gz src
  else
    tar -cf dist/bundle.tar src
  fi
}
SH
cat > .github/workflows/release.yml <<'YML'
name: release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Bundle
        run: source scripts/package.sh && build_bundle --compress
YML
git add scripts/package.sh .github/workflows/release.yml
git commit -q -m "feat(release): ship a compressed bundle" -m "The uncompressed tarball is over the release asset size limit. Refs REL-12."

git checkout -q main
cat > scripts/package.sh <<'SH'
#!/usr/bin/env bash
# Sourced by the release workflow.

make_bundle() {
  tar -cf dist/bundle.tar src
}
SH
git add scripts/package.sh
git commit -q -m "refactor(release): rename build_bundle to make_bundle" -m "Every packaging helper is make_*; build_* is reserved for compile steps. Refs REL-9."

git checkout -q feature/compress
git merge --no-commit --no-ff main >/dev/null 2>&1 || true
test -f .git/MERGE_HEAD
test "$(git diff --name-only --diff-filter=U)" = "scripts/package.sh"
grep -q 'build_bundle --compress' .github/workflows/release.yml
