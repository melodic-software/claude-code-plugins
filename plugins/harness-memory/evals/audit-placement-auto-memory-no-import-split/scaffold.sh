#!/usr/bin/env bash
# Seeds a repository whose 300-line CLAUDE.md is half a running log of build
# learnings and half a walkthrough of the Terraform modules under infra/.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

modules="network dns cdn storage database cache queue search compute registry secrets iam
monitoring logging alerts backups"
mkdir -p infra/modules src
for m in $modules; do
  mkdir -p "infra/modules/$m"
  printf 'variable "env" {}\n' >"infra/modules/$m/variables.tf"
done
printf 'package main\n' >src/main.go

{
  echo "# Fieldnotes app"
  echo
  echo "## Things we figured out about the build"
  echo
  n=1
  while [[ "$n" -le 117 ]]; do
    case $((n % 4)) in
    0) echo "- Build note $n: \`go test ./...\` needs CGO_ENABLED=0 on the CI image, or the sqlite driver fails to link." ;;
    1) echo "- Build note $n: the generated mocks go stale after an interface change; rerun \`make mocks\` before testing." ;;
    2) echo "- Build note $n: \`make lint\` caches results under .cache/lint; delete it when the linter version changes." ;;
    *) echo "- Build note $n: the release build reads VERSION from the latest tag, so a shallow clone builds as 0.0.0." ;;
    esac
    n=$((n + 1))
  done
  echo
  echo "## Terraform module layout (infra/)"
  echo
} >CLAUDE.md
for m in $modules; do
  {
    echo "### infra/modules/$m"
    echo
    echo "- Inputs: \`env\`, plus the outputs of the modules it depends on."
    echo "- State lives in the \`$m\` workspace of the shared backend."
    echo "- Apply it from \`infra/envs/<env>\`, never from the module directory."
    echo "- A rename here moves resources: add a \`moved\` block in the same change."
    echo "- Plan output for $m is reviewed by the platform team before apply."
    echo "- Tag every resource in $m with \`owner\` and \`env\`."
    echo "- Its outputs are listed in \`infra/modules/$m/outputs.tf\`; keep them stable across releases."
    echo "- Destroying $m in production needs a second approver on the plan."
    echo
  } >>CLAUDE.md
done

git add -A
git commit -q -m "chore: initial commit"
