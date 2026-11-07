#!/usr/bin/env bash
# Node package a depends on sibling package b through file:../b; Go module c replaces its
# example.com/foo requirement with ../a, which also holds a go.mod; a Gemfile sits at the root.
# The convention home declares architecture_dir docs/architecture.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs Gemfile a b c
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh"
mkdir -p a b c

cat >a/package.json <<'JSON'
{
  "name": "a",
  "version": "1.0.0",
  "dependencies": {
    "b": "file:../b"
  }
}
JSON

cat >a/go.mod <<'GO'
module example.com/foo

go 1.22
GO

cat >b/package.json <<'JSON'
{
  "name": "b",
  "version": "1.0.0"
}
JSON

cat >c/go.mod <<'GO'
module example.com/c

go 1.22

require example.com/foo v0.0.0

replace example.com/foo => ../a
GO

cat >Gemfile <<'RUBY'
source "https://rubygems.org"

gem "rake", "~> 13.0"
RUBY

git add -A
git commit -q -m "Node packages a and b, Go module c, and a Gemfile"
mkdir -p docs/architecture
