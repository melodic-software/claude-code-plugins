#!/usr/bin/env bash
# Seeds a repository whose root CLAUDE.md is the one line `@AGENTS.md` over a
# 240-line AGENTS.md, with a nested plugins/foo/AGENTS.md that nothing imports and
# a rule last committed by the standards sync.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

printf '@AGENTS.md\n' >CLAUDE.md

areas="api auth billing cli config docs exporter importer jobs mailer metrics plugins queue
scheduler search storage telemetry ui webhooks workers"
{
  echo "# Lighthouse"
  echo
  echo "Status-page platform. Build with \`make build\`, test with \`make test\`."
  echo
  for a in $areas; do
    echo "## $a"
    echo
    echo "- Code lives in \`src/$a/\`; tests sit beside it as \`*_test.go\`."
    echo "- Run \`make test-$a\` after changing anything here."
    echo "- Public types in $a are part of the plugin API; change them only with a deprecation note."
    echo "- Logs from $a carry the \`component=$a\` field."
    echo "- Config keys for $a live under \`$a.\` in \`config/default.yaml\`."
    echo "- Errors returned by $a wrap the cause with \`fmt.Errorf(\"$a: %w\", err)\`."
    echo "- Metrics for $a are prefixed \`lighthouse_${a}_\`."
    echo "- Feature flags for $a are read once at start."
    echo "- Owners for $a are listed in CODEOWNERS."
    echo
  done
} >AGENTS.md
n=1
while [[ "$(grep -c . AGENTS.md)" -lt 240 ]]; do
  printf -- "- Shared setting \`LH_SHARED_%02d\` is read by every component.\n" "$n" >>AGENTS.md
  n=$((n + 1))
done

mkdir -p plugins/foo src
cat >plugins/foo/AGENTS.md <<'MD'
# foo plugin

- This plugin talks to the upstream API through `client.go` only.
- Run `make test-plugin-foo` after any change here.
MD
printf 'package foo\n' >plugins/foo/client.go
printf 'package main\n' >src/main.go

git add -A
git commit -q -m "chore: initial commit"

mkdir -p .claude/rules
cat >.claude/rules/pr-body-contract.md <<'MD'
---
description: "Pull request titles and bodies follow the shared PR contract"
---

# PR contract

- Title pull requests in Conventional Commits form.
- Open the body with a closing keyword or a Refs line.
MD
git add .claude/rules/pr-body-contract.md
git -c user.name=standards-sync -c user.email=standards-sync@example.invalid \
  commit -q -m "chore: sync standards components"
