#!/usr/bin/env bash
# Seeds one state of a shared fixture repository into a directory and commits it on main, the
# workspace sources/harness/run-cell.sh built for each run.
#
#   tarnquill    .NET 10 solution with the `tq` team CLI
#   brackenfold  Python package with the `bfk` team CLI
#
#   bare              AGENTS.md describes the repository only
#   conventions-only  AGENTS.md also holds the team's tooling conventions
#   converged         docs/conventions/developer-experience.md plus the setup pointer line
#   legacy            (tarnquill only) the older .claude/developer-experience.md and its block
#
# The files are what sources/harness/build-fixtures.py writes, each with a .txt suffix so no
# linter or test runner reads it as source. Tarnquill.sln is fixed in place of the one
# `dotnet new sln` generates, so its project GUIDs never change. The converged pointer line comes
# from the shipped skills/setup/scripts/pointer-line.sh. The legacy block names a path under
# .claude/, which that helper refuses, so it is copied as written.
#
# Usage: seed.sh <tarnquill|brackenfold> <state> [dir]   (dir defaults to the current directory)
# Exit: 0 seeded, 2 usage error; any other status is the failing command's.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$here/../../skills/setup/scripts/pointer-line.sh"
state_files="$here/states"

usage() {
  echo "usage: seed.sh <tarnquill|brackenfold> <bare|conventions-only|converged|legacy> [dir]" >&2
  exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage
name="$1" state="$2" dest="${3:-.}"

case "$name" in
  tarnquill)
    files=(
      .gitignore AGENTS.md Makefile README.md Tarnquill.sln
      src/Tarnquill.Cli/Tarnquill.Cli.csproj
      src/Tarnquill.Cli/Program.cs
      src/Tarnquill.Cli/Infrastructure/ProcessRunner.cs
      src/Tarnquill.Cli/Commands/CommitCommand.cs
      src/Tarnquill.Cli/Commands/ItemCommentCommand.cs
      src/Tarnquill.Cli/Commands/EnvCheckCommand.cs
      src/Tarnquill.Core/Tarnquill.Core.csproj
      src/Tarnquill.Core/Paging.cs
      tests/Tarnquill.Core.Checks/Tarnquill.Core.Checks.csproj
      tests/Tarnquill.Core.Checks/Program.cs
      scripts/build.sh scripts/build.ps1 scripts/clean-outbox.sh
    )
    conventions=tarnquill-conventions.md
    conventions_file=tarnquill-developer-experience.md
    ;;
  brackenfold)
    files=(
      .gitignore AGENTS.md Makefile README.md pyproject.toml
      bfk/__init__.py bfk/cli.py bfk/proc.py bfk/release.py bfk/store.py bfk/text.py
      data/accounts.jsonl
      tests/test_text.py
      scripts/README.md scripts/run_tests.sh scripts/test.sh scripts/seed_fixtures.py
      scripts/release.ps1
    )
    conventions=brackenfold-conventions.md
    conventions_file=brackenfold-developer-experience.md
    ;;
  *) usage ;;
esac
case "$state" in
  bare | conventions-only | converged) ;;
  legacy) [[ "$name" == tarnquill ]] || usage ;;
  *) usage ;;
esac

mkdir -p "$dest"
cd "$dest"
for f in "${files[@]}"; do
  mkdir -p "$(dirname "$f")"
  cp "$here/$name/$f.txt" "$f"
done
chmod +x scripts/*.sh
if [[ "$name" == brackenfold ]]; then
  : >tests/__init__.py
fi

case "$state" in
  conventions-only)
    printf '\n' >>AGENTS.md
    cat "$state_files/$conventions.txt" >>AGENTS.md
    ;;
  converged)
    mkdir -p docs/conventions
    cp "$state_files/$conventions_file.txt" docs/conventions/developer-experience.md
    bash "$helper" apply --root . --path docs/conventions/developer-experience.md --yes >/dev/null
    ;;
  legacy)
    printf '\n' >>AGENTS.md
    cat "$state_files/tarnquill-legacy-block.md.txt" >>AGENTS.md
    cp "$state_files/tarnquill-legacy-CLAUDE.md.txt" CLAUDE.md
    mkdir -p .claude
    cp "$state_files/tarnquill-legacy-developer-experience.md.txt" .claude/developer-experience.md
    ;;
  *) ;;
esac

git init -q -b main
git add -A
git -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false commit -q -m scaffold
