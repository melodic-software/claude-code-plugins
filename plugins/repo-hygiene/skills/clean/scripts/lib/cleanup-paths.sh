# shellcheck shell=bash
# Sourceable path registry for the clean scripts.
# SSOT: reference/cleanup-config.md — drift detected by cleanup-paths.test.sh
# shellcheck disable=SC2034

# Universal find exclusions (cleanup-config.md intro)
CLEAN_FIND_EXCLUDE_GIT='*/.git/*'
CLEAN_FIND_EXCLUDE_VENV='*/.venv/*'
CLEAN_FIND_EXCLUDE_NODE_MODULES='*/node_modules/*'

# caches — explicit repo-root paths (trailing slash = directory; no slash on files).
# Generic across ecosystems; regenerated on the next tool run.
CLEAN_CACHE_EXPLICIT=(
  .pytest_cache
  .ruff_cache
  .mypy_cache
  .turbo
  .vs
  .codex/logs
)

# caches — explicit repo-root files (none generic by default).
CLEAN_CACHE_EXPLICIT_FILES=()

# caches — recursive directory name patterns (**/name/)
CLEAN_CACHE_FIND_DIR_NAMES=(
  __pycache__
)

# caches — recursive file globs
CLEAN_CACHE_FIND_FILE_GLOBS=(
  '*.tsbuildinfo'
)

# build — directory names for find -name
CLEAN_BUILD_DIR_NAMES=(
  bin
  obj
  build
  dist
  out
  target
  TestResults
)

CLEAN_BUILD_FILE_GLOBS=(
  '*.binlog'
)

# build — .NET clean driver. The solution/project file is detected at runtime by
# clean-build.sh (any *.slnx / *.sln at the repo root), never hardcoded — the
# universal bin/obj globs above remove output directly when dotnet is absent.

# git — safe prune mutations
GIT_PRUNE_OPS=(
  'git worktree prune'
  'git remote prune origin'
  'git gc --auto --quiet'
)

# Protected path segments / globs — never delete (substring match on normalized
# path). Conservative universal set: deleting any of these risks losing a
# consumer's dependencies, credentials, or IDE state.
CLEAN_PROTECTED_SUBSTRINGS=(
  '/node_modules/'
  '/.venv/'
  '/vendor/'
  '/.vscode/'
  '/.idea/'
  '/.azure-cli/'
  '/.aws/'
  '/.gcloud/'
  '/.codex/config.toml'
  '/.codex/hooks.json'
  '/.codex/rules/'
)

# Skill data dirs: .claude/skills/*/data/ — checked in clean_path_is_protected

# Protected branch name patterns (git-branch-cleanup.md §4.5)
CLEAN_PROTECTED_BRANCH_EXACT=(
  main
  master
  develop
)

CLEAN_PROTECTED_BRANCH_GLOBS=(
  'release/*'
  'hotfix/*'
)

CLEAN_STALE_BRANCH_DAYS=90

# tree (git clean) preserve patterns — gitignore syntax for `git clean -e <pat>`.
# SSOT for the `tree` tier's default-preserve set; aligned with the "Protected
# paths" classes in reference/cleanup-config.md (drift-checked by
# cleanup-paths.test.sh). Three tiers gate which patterns apply:
#   SECRETS   — always preserved unless --include-secrets (unrecoverable)
#   SKILLDATA — always preserved (user synthesis; no flag removes it)
#   DEPS      — preserved unless --include-deps (rebuildable; keeping them makes
#               the default clean junction-proof — git never descends into
#               node_modules, so reparse-point traversal into tracked source
#               cannot happen)
CLEAN_TREE_PRESERVE_SECRETS=(
  '.env*'
  '*.local.json'
  '*.local.jsonc'
  '*.local.md'
  '*.csproj.user'
  '*.suo'
  '.vscode/'
  '.idea/'
  '.azure-cli/'
  '.aws/'
  '.gcloud/'
  '.codex/config.toml'
  '.codex/hooks.json'
  '.codex/rules/'
)

CLEAN_TREE_PRESERVE_SKILLDATA=(
  '.claude/skills/*/data/'
)

CLEAN_TREE_PRESERVE_DEPS=(
  'node_modules/'
  '.venv/'
  'vendor/'
)

cleanup_paths_config_file() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s/../../reference/cleanup-config.md' "$script_dir"
}
