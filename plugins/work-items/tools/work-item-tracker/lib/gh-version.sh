# shellcheck shell=bash
# GitHub CLI version helpers. Sourced by the dispatcher (fail-loud gate on
# native-surface flags) and the GitHub adapter (omit 2.94+ --json fields on
# older gh so get-item and a plain create-item still emit).
#
# Floor: gh 2.94.0 introduced issue types, sub-issues, and dependencies
# (`--parent`, `--blocked-by`, `--add-blocked-by`, and the issueType / parent /
# subIssues / blockedBy --json fields). Official changelog:
# https://github.blog/changelog/2026-06-10-manage-sub-issues-types-and-dependencies-from-github-cli/

[[ -n "${_WIT_GH_VERSION_LOADED:-}" ]] && return 0
readonly _WIT_GH_VERSION_LOADED=1

readonly WIT_GH_NATIVE_SURFACE_MAJOR=2
readonly WIT_GH_NATIVE_SURFACE_MINOR=94

# wit_gh_version_raw — echo MAJOR.MINOR from `gh --version`, or empty when the
# binary is missing or the first line does not match `gh version X.Y…`.
wit_gh_version_raw() {
  local out
  out="$(gh --version 2>/dev/null)" || true
  out="${out%%$'\n'*}"
  if [[ "$out" =~ ^gh\ version\ ([0-9]+\.[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

# wit_gh_has_native_surface — 0 when gh is present and >= 2.94. Does not exit.
wit_gh_has_native_surface() {
  local raw major minor
  command -v gh >/dev/null 2>&1 || return 1
  raw="$(wit_gh_version_raw)"
  major="${raw%%.*}"
  minor="${raw#*.}"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  ((major > WIT_GH_NATIVE_SURFACE_MAJOR ||
    (major == WIT_GH_NATIVE_SURFACE_MAJOR && minor >= WIT_GH_NATIVE_SURFACE_MINOR)))
}
