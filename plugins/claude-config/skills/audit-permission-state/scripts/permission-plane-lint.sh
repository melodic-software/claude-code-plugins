#!/usr/bin/env bash
# permission-plane-lint.sh — findings over the permission plane: configuration
# that is written but never read, and allow rules that cannot match.
#
# Every check here answers the same shape of question: the operator wrote
# something believing it takes effect, and it does not. The harness is not
# silent about all of these — several emit a startup warning — but a warning
# fires at session start, in one session, for one machine's scopes. This reads
# every scope at once, before a session, and says which file the dead entry is
# in.
#
# Input: permission-state.sh records on stdin (rule + conf + surface records).
# With no piped input the reader is run directly and its status propagated.
#
# Output:
#   finding <severity> [<check>] <scope> <detail>
#   lint summary findings=<n> checks_run=<n>
#
#   severity  error | warning   (review plugin's severity vocabulary)
#
# Checks, each citing the mechanic it follows from — see reference/criteria.md:
#   C2-autoMode      autoMode.* in a scope the classifier does not read
#   C2-defaultMode   defaultMode:"auto" in project or local settings
#   C2-planMode      useAutoModeDuringPlan in shared project settings
#   C5-disableType   disableAutoMode typed as a boolean, not the string "disable"
#   C6-winPath       a doubled-backslash Windows path in a rule
#   C6-contentField  a parameter-form rule on a tool's primary content field
#   C6-uncoveredPath a path rule on a tool whose path rules are never consulted
#   C6-colonStar     `:*` used anywhere but at the end of a pattern
#
# Prerequisites: jq (required for correctness — the conf/settings reads are JSON).
#
# Usage:
#   permission-state.sh | permission-plane-lint.sh
#   permission-plane-lint.sh [--help]

set -uo pipefail

usage() {
  cat <<'EOF'
permission-plane-lint.sh — find permission configuration that is written but never read.

Usage: permission-state.sh | permission-plane-lint.sh
       permission-plane-lint.sh [--help]

Emits "finding <severity> [<check>] <scope> <detail>" and a summary line.
Advisory: always exits 0 when it ran. Exit 2 means it could not run at all
(no scope records on input), never "nothing found".

Reads only. Never writes any settings file.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
"") ;;
*)
  echo "ERROR: unknown argument '$1'" >&2
  exit 2
  ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

if [[ -t 0 ]]; then
  STATE_SCRIPT="${BASH_SOURCE[0]%/*}/permission-state.sh"
  if [[ ! -r "$STATE_SCRIPT" ]]; then
    echo "ERROR: cannot read $STATE_SCRIPT — nothing to lint" >&2
    exit 2
  fi
  records="$(bash "$STATE_SCRIPT")" || exit $?
else
  records="$(cat)"
fi

# Settings paths per scope come from the surface records, so this script never
# re-derives a location the reader already resolved. A scope the reader could
# not open contributes no findings and is not claimed clean.
lint_out="$(printf '%s\n' "$records" | awk '
function text_of(start,   i, s) {
  s = $start
  for (i = start + 1; i <= NF; i++) s = s " " $i
  return s
}
function finding(sev, check, scope, detail) {
  print "finding " sev " [" check "] " scope " " detail
  n_findings++
}

$1 == "rule" {
  rules[++n_rules] = $2 SUBSEP $4 SUBSEP text_of(5)
  next
}
$1 == "conf" { conf[$2 SUBSEP $4] = text_of(5); next }
$1 == "NOTE:" { next }
NF >= 3 {
  n_surfaces++
  path_of[$1] = $4
  status_of[$1] = $3
  next
}

END {
  if (n_surfaces == 0) exit 2

  # --- C2: configuration written where nothing reads it ----------------------
  #
  # Three separate gates, reported separately. Merging them would hide that they
  # have different scope sets and different version histories, and an operator
  # fixing one would believe they had fixed all three.
  #
  # "The classifier does not read autoMode from project settings in
  # .claude/settings.json or .claude/settings.local.json." Before v2.1.207 it
  # also read local settings, so a local-scope section was live on an older
  # harness -- the finding says so rather than implying it never worked.
  split("project local startdir-local", dead_automode, " ")
  for (i in dead_automode) {
    s = dead_automode[i]
    if ((s SUBSEP "autoModePresent") in conf) {
      extra = (s == "project") ? "" : " (read from local settings before v2.1.207, so this may have been live on an older harness)"
      finding("error", "C2-autoMode", s, "an autoMode section here is never read: the classifier reads autoMode from user settings, managed settings, and inline --settings/SDK JSON only" extra)
    }
  }

  # "Claude Code ignores defaultMode: auto in project and local settings…
  # v2.1.142 and later ignore auto from those files so a repository cannot grant
  # itself auto mode." Only the value `auto` is dead; other modes are read here.
  for (i in dead_automode) {
    s = dead_automode[i]
    k = s SUBSEP "defaultMode"
    if (k in conf && conf[k] == "\"auto\"")
      finding("error", "C2-defaultMode", s, "defaultMode:\"auto\" is ignored in project and local settings so a repository cannot grant itself auto mode (v2.1.142 and later; before that, project settings could set it) — set it in user or managed settings instead")
  }

  # "Not read from shared project settings." That names .claude/settings.json
  # specifically, so a local-settings occurrence is NOT claimed dead here --
  # claiming it would be asserting a restriction the page does not state.
  if ((("project") SUBSEP "useAutoModeDuringPlan") in conf)
    finding("error", "C2-planMode", "project", "useAutoModeDuringPlan is not read from shared project settings — move it to user settings, where it takes effect")

  # --- C5: disableAutoMode typed as a boolean --------------------------------
  #
  # "set permissions.disableBypassPermissionsMode or permissions.disableAutoMode
  # to \"disable\" in any settings file" -- the STRING. A boolean is accepted by
  # JSON and does nothing, which is the worst possible outcome for a lock-out
  # switch: the operator believes auto mode is disabled and it is not. Checked
  # at BOTH documented key paths, in EVERY scope: it is not managed-only.
  split("managed user project local startdir-local", all_scopes, " ")
  split("disableAutoMode permissions.disableAutoMode", disable_keys, " ")
  for (i in all_scopes) {
    for (j in disable_keys) {
      k = all_scopes[i] SUBSEP disable_keys[j]
      if (!(k in conf)) continue
      if (conf[k] != "\"disable\"")
        finding("error", "C5-disableType", all_scopes[i], disable_keys[j] " is " conf[k] ", but the documented value is the STRING \"disable\" — any other value is accepted and silently does nothing, so auto mode is NOT disabled here")
    }
  }

  # --- C6: allow rules that cannot match -------------------------------------
  #
  # Primary content fields, verbatim from the permissions page: command for Bash
  # and PowerShell, file_path for Read/Edit/Write, path for Grep and Glob,
  # notebook_path for NotebookEdit, url for WebFetch. A parameter-form rule on
  # one of these is ignored outright.
  content_field["Bash"] = "command";        content_field["PowerShell"] = "command"
  content_field["Read"] = "file_path";      content_field["Edit"] = "file_path"
  content_field["Write"] = "file_path";     content_field["Grep"] = "path"
  content_field["Glob"] = "path";           content_field["NotebookEdit"] = "notebook_path"
  content_field["WebFetch"] = "url"

  # File permissions are checked against Edit(path) and Read(path) rules ONLY.
  # A path rule for one of these is accepted and never consulted.
  split("Write NotebookEdit Glob MultiEdit", uncovered_list, " ")
  for (i in uncovered_list) uncovered[uncovered_list[i]] = 1

  for (r = 1; r <= n_rules; r++) {
    split(rules[r], f, SUBSEP)
    scope = f[1]; kind = f[2]; text = f[3]
    p = index(text, "(")
    tool = p ? substr(text, 1, p - 1) : text
    body = p ? substr(text, p + 1, length(text) - p - 1) : ""

    # A bare tool-name rule with no path is legitimate and matches at the tool
    # level everywhere -- the page says so explicitly, and flagging it would be
    # a false positive on the most ordinary rule shape there is.
    if (body == "") continue

    # Doubled backslashes: on Windows a rule path is normalized to POSIX form
    # before matching, so a JSON-escaped Windows path never matches anything.
    if (index(body, "\\\\") > 0)
      finding("error", "C6-winPath", scope, text " — a Windows-style path in a rule cannot match: rule paths are normalized to POSIX form (C:\\Users\\alice becomes /c/Users/alice), so use //c/** form instead")

    # `:*` is recognized only at the end of a pattern; elsewhere the colon is a
    # literal, so the rule silently matches nothing it was meant to.
    cs = index(body, ":*")
    if (cs > 0 && cs + 1 < length(body))
      finding("error", "C6-colonStar", scope, text " — the :* form is only recognized at the END of a pattern; here the colon is treated as a literal character and the rule will not match what it looks like it matches")

    # Parameter form is `Tool(param:value)`. It is only a content-field defect
    # when the named parameter IS the primary content field for that tool.
    colon = index(body, ":")
    if (colon > 1) {
      param = substr(body, 1, colon - 1)
      if (tool in content_field && param == content_field[tool])
        finding("error", "C6-contentField", scope, text " — a rule cannot match a tool primary content field by parameter (" tool " uses " content_field[tool] "); Claude Code ignores this rule and warns at startup")
    }

    # A path-shaped rule on a tool whose path rules are never consulted. Only
    # allow/deny path shapes are relevant, and only when the body actually looks
    # like a path rather than a parameter form.
    if (tool in uncovered && colon == 0)
      finding("warning", "C6-uncoveredPath", scope, text " — file permissions are checked against Edit(path) and Read(path) rules only, so a path rule for " tool " is accepted but never consulted (warns at startup, v2.1.210+; a Glob rule passed in --allowedTools is the documented exception)")
  }

  print "lint summary findings=" n_findings + 0 " checks_run=8"
}
')" || {
  echo "ERROR: no scope records on input — permission-plane-lint.sh will not report a clean plane it never read" >&2
  exit 2
}

printf '%s\n' "$lint_out"
