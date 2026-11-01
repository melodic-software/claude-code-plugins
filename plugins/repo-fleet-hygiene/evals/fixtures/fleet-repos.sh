#!/usr/bin/env bash
# Writes a made-up Git fleet into the current directory. Every remote is a bare repository under
# ./remotes, reached by a relative path, so nothing touches the network or a real checkout.
#
#   fleet-repos.sh audit   fleet/alpha (merged and unmerged local branches, one linked worktree
#                          whose directory is gone) and fleet/beta (clean, on main)
#   fleet-repos.sh sync    fleet/alpha (clean, on a feature branch) and fleet/beta (on main, one
#                          commit behind its remote)
#   fleet-repos.sh single  one checkout in the current directory with a merged branch and caches
#
# audit and sync also write .claude/repo-fleet-hygiene.conf naming ./fleet, so a run that drops the
# explicit scope still resolves to this fleet rather than to the no-scope ladder.
set -euo pipefail

# The scaffold runs as the operator, outside the sandbox: keep their global and system Git config
# (hooks, signing, URL rewrites) out of every command below.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

g() { git -c user.email=eval@example.invalid -c user.name=eval -c commit.gpgsign=false "$@"; }

commit() {
  local dir="$1" file="$2" msg="$3"
  printf '%s\n' "$msg" >>"$dir/$file"
  g -C "$dir" add -- "$file"
  g -C "$dir" commit -q -m "$msg"
}

# new_repo <name>: an empty bare remote plus a clone under fleet/ with one commit on main pushed.
new_repo() {
  local name="$1"
  g init -q --bare -b main "remotes/$name.git"
  mkdir -p "fleet/$name"
  g init -q -b main "fleet/$name"
  g -C "fleet/$name" remote add origin "../../remotes/$name.git"
  commit "fleet/$name" README.md "# $name"
  g -C "fleet/$name" push -q origin main
  g -C "fleet/$name" branch -q --set-upstream-to=origin/main main
}

write_config() {
  mkdir -p .claude
  cat >.claude/repo-fleet-hygiene.conf <<'CONF'
[fleet]
  root = ../fleet
  maxDepth = 3
CONF
}

case "${1:-}" in
audit)
  mkdir -p remotes fleet wt
  new_repo alpha
  new_repo beta
  g -C fleet/alpha switch -q -c feature/invoice-totals
  commit fleet/alpha totals.txt "feat: invoice totals"
  g -C fleet/alpha switch -q main
  g -C fleet/alpha merge -q --no-ff -m "Merge feature/invoice-totals" feature/invoice-totals
  g -C fleet/alpha push -q origin main
  g -C fleet/alpha switch -q -c spike/new-parser
  commit fleet/alpha parser.txt "wip: new parser"
  g -C fleet/alpha switch -q main
  g -C fleet/alpha worktree add -q ../../wt/alpha-old-spike -b spike/old-idea
  rm -r -- wt/alpha-old-spike
  write_config
  ;;
sync)
  mkdir -p remotes fleet
  new_repo alpha
  new_repo beta
  g -C fleet/alpha switch -q -c feature/report-export
  commit fleet/alpha export.txt "feat: report export"
  g clone -q remotes/beta.git beta-upstream
  commit beta-upstream CHANGES.md "fix: upstream change"
  g -C beta-upstream push -q origin main
  rm -r -- beta-upstream
  write_config
  ;;
single)
  g init -q -b main .
  commit . README.md "# ledger-cli"
  g switch -q -c fix/rounding
  commit . rounding.txt "fix: rounding"
  g switch -q main
  g merge -q --no-ff -m "Merge fix/rounding" fix/rounding
  g switch -q -c feature/csv-import
  commit . csv.txt "wip: csv import"
  g switch -q main
  mkdir -p node_modules/left-pad build
  printf 'module.exports = 1;\n' >node_modules/left-pad/index.js
  printf 'compiled\n' >build/app.js
  printf 'node_modules/\nbuild/\n' >.gitignore
  g add .gitignore
  g commit -q -m "chore: ignore caches"
  ;;
*)
  printf 'usage: fleet-repos.sh audit|sync|single\n' >&2
  exit 2
  ;;
esac
