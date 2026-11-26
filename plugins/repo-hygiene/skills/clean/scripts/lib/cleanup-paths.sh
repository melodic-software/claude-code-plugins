# shellcheck shell=bash
# SSOT: reference/cleanup-config.md — drift detected by cleanup-paths.test.sh
# shellcheck disable=SC2034

CLEAN_PRUNE_DIRS=(.git node_modules .venv)

CLEAN_FIND_EXCLUDE_GIT='*/.git/*'

CLEAN_CACHE_EXPLICIT=(
  .pytest_cache
  .ruff_cache
  .mypy_cache
  .turbo
  .vs
  .codex/logs
)

CLEAN_CACHE_EXPLICIT_FILES=()

CLEAN_CACHE_FIND_DIR_NAMES=(
  __pycache__
)

CLEAN_CACHE_FIND_FILE_GLOBS=(
  '*.tsbuildinfo'
)

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

GIT_PRUNE_OPS=(
  'git worktree prune'
  'git remote prune origin'
  'git gc --auto --quiet'
)

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

CLEAN_RETENTION_PREWIPE_DAYS="${CLEAN_RETENTION_PREWIPE_DAYS:-30}"
CLEAN_RETENTION_CLAUDE_DAYS="${CLEAN_RETENTION_CLAUDE_DAYS:-30}"
CLEAN_RETENTION_PLAN_DAYS="${CLEAN_RETENTION_PLAN_DAYS:-90}"
CLEAN_RETENTION_STRANDED_DAYS="${CLEAN_RETENTION_STRANDED_DAYS:-30}"

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
  printf '%s/../../reference/cleanup-config.md' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}
