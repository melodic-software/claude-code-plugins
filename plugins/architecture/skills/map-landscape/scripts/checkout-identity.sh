# Checkout identity shared by the map-landscape collectors.
#
# Claim: a clone's repository identity is the owner and repository path segments
# of its `origin` URL when that URL's host is github.com, not the directory the
# checkout sits in. `git remote get-url origin` returns that configured URL,
# after insteadOf expansion. GitHub's clone URLs are
# `https://github.com/OWNER/REPO.git` and `git@github.com:OWNER/REPO.git`, so
# OWNER and REPO are those two segments. The record stores REPO as `name` and
# as an edge's `from`. The renderer already joins the separate `owner` field
# with `name`, and a directory that is already named REPO keeps its record key.
# An origin whose host is not github.com stores no repository identity here, and
# the directory name remains.
# Basis: https://git-scm.com/docs/git-remote (`get-url`) and
# https://docs.github.com/en/get-started/git-basics/about-remote-repositories
# (HTTPS and SSH clone URL shapes; the default remote name `origin`).
# As of: 2026-09-28.
# Recheck: GitHub documents a clone URL whose repository is not the OWNER and
# REPO path segments, or `git remote get-url` stops returning the configured
# origin URL.
#
# Sourced, never executed. The caller has set `repo` to the absolute checkout.

# The origin's path on github.com, `owner/repo...`, when the remote's host IS
# github.com. The host is the authority with the scheme and user info removed,
# compared case-insensitively, with `www.` allowed. With a scheme, a port of
# digits (possibly empty, as RFC 3986 allows) is removed; any other `:` after
# the host is not a port and the URL names no github.com path. So
# `evilgithub.com`, `github.com.evil.example`, `api.github.com`, a
# `/github.com/` path on another server, a `file://` path and a relative path
# all fail. A URL without a scheme counts only in the scp form `host:path`.
github_remote_path() {
  local url host rest scheme=0 result=1 had_nocase=0
  # shellcheck disable=SC2154 # `repo` is the checkout the sourcing collector resolved
  url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 1
  url="${url%/}"
  url="${url%.git}"
  [[ "$url" == *://* ]] && scheme=1 && url="${url#*://}"
  [[ "${url%%/*}" == *@* ]] && url="${url#*@}"
  host="${url%%[:/]*}"
  rest="${url#"$host"}"
  if [[ $scheme -eq 1 ]]; then
    [[ "$rest" =~ ^:[0-9]*/ ]] && rest="${rest#:*/}"
    [[ "$rest" == :* ]] && return 1
    rest="${rest#/}"
  else
    [[ "$rest" == :* ]] || return 1
    rest="${rest#:}"
    rest="${rest#/}"
  fi
  # A doubled slash (`host//owner/repo`, including an insteadOf rewrite of an
  # scp URL that already had a slash) leaves an empty segment. It is not part
  # of the repository path.
  while [[ "$rest" == /* ]]; do rest="${rest#/}"; done
  shopt -q nocasematch && had_nocase=1
  shopt -s nocasematch
  [[ "$host" == github.com || "$host" == www.github.com ]] && result=0
  [[ $had_nocase -eq 1 ]] || shopt -u nocasematch
  [[ $result -eq 0 && -n "$rest" ]] || return 1
  printf '%s' "$rest"
}

# REPO from a github.com origin, else the checkout directory's name. A path
# with no owner/repo pair is not a repository identity.
checkout_repository_name() {
  local path segment fallback
  # shellcheck disable=SC2154
  fallback="$(basename "$repo")"
  path="$(github_remote_path)" || {
    printf '%s' "$fallback"
    return 0
  }
  case "$path" in
  */*) segment="${path#*/}" ;;
  *)
    printf '%s' "$fallback"
    return 0
    ;;
  esac
  segment="${segment%%/*}"
  case "$segment" in
  "" | . | .. | *[!A-Za-z0-9_.-]*)
    printf '%s' "$fallback"
    ;;
  *) printf '%s' "$segment" ;;
  esac
}
