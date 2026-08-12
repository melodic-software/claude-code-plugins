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
#   C6-winPath       a drive-letter or UNC Windows path, which never matches
#   C6-contentField  a parameter-form rule on a tool's primary content field
#   C6-uncoveredPath a path rule on a tool whose path rules are never consulted
#   C6-colonStar     `:*` mid-pattern in a command-prefix rule (not the parameter form)
#   C6-colonStarAmbiguous  mid-pattern `:*` with no trailing space — indistinguishable from a parameter form (warning)
#   C6-allowParam    parameter-form matching in an allow rule (deny/ask only)
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
# The `word` in `Tool(word:...)`, or "" when the body carries no colon prefix.
function prefix_of(b,   c, p) {
  c = index(b, ":")
  if (c < 2) return ""
  p = substr(b, 1, c - 1)
  sub(/[ \t]+$/, "", p)
  return p
}
# Everything after the first colon -- the value half of `word:value`.
function value_of(b,   c) {
  c = index(b, ":")
  return c ? substr(b, c + 1) : ""
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

  # Top-level parameters the page names by example, on tools whose OWN specifier
  # syntax is something else entirely (a path, or a command). Only these are
  # unambiguously the parameter form: `WebFetch(domain:host)` is documented as
  # the WebFetch syntax itself and `Bash(npm:*)` is a command prefix, so neither can
  # be told apart from a parameter by shape alone and neither is listed here.
  # Documented per-tool prefix forms where a wildcard is legal ANYWHERE in the
  # value, so the mid-pattern `:*` rule does not apply to them.
  documented_param["WebFetch" SUBSEP "domain"] = 1

  param_only["Agent" SUBSEP "model"] = 1
  param_only["Agent" SUBSEP "isolation"] = 1
  param_only["Bash" SUBSEP "run_in_background"] = 1
  param_only["PowerShell" SUBSEP "run_in_background"] = 1

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

    # A Windows-style path in a rule: rule paths are normalized to POSIX form
    # before matching, so `C:\Users\alice` never matches anything.
    #
    # This check has been wrong in BOTH directions. It first tested for a doubled
    # backslash -- the JSON SOURCE spelling -- which `jq -r` decodes away, so it
    # was dead in the real pipeline. Testing a bare backslash instead made it
    # worse than dead: backslashes are ordinary in shell rules (`Bash(echo \n *)`,
    # a regex `sed 's/\./_/g'`, an escape inside a quoted string), so every one
    # became a severity-`error` finding carrying Windows-path advice, and the one
    # true finding drowned.
    #
    # So the test is on SHAPE, not on the character: a drive-letter prefix
    # (`C:\`) or a UNC prefix (`\\host`), the two forms that are actually a
    # Windows path. A backslash anywhere else is somebody escaping something.
    drive = match(body, /(^|[^A-Za-z0-9])[A-Za-z]:\\/)
    unc = (index(body, "\\\\") == 1) || (index(body, "(\\\\") > 0)
    if (drive > 0)
      finding("error", "C6-winPath", scope, text " — a Windows-style path in a rule cannot match: rule paths are normalized to POSIX form (C:\\Users\\alice becomes /c/Users/alice), so use the //c/** form instead")
    else if (unc)
      finding("error", "C6-winPath", scope, text " — a UNC path in a rule cannot match: rule paths are normalized to POSIX form before matching, so a UNC host/share prefix never matches. Express the target as a POSIX-form path")

    # `:*` is recognized only at the end of a pattern; elsewhere the colon is a
    # literal, so the rule silently matches nothing it was meant to.
    #
    # The documented mechanic is about COMMAND PREFIX patterns -- "In a pattern
    # like `Bash(git:* push)`, the colon is treated as a literal character" --
    # not about the parameter form, where a mid-body `*` is documented and
    # working: "WebFetch rules use a `domain:` prefix and match against the
    # hostname… supports `*` wildcards." Firing on `WebFetch(domain:*.example.com)`
    # called a documented working rule broken.
    # The exemption is by GRAMMAR, not by a list of parameter names. The page
    # says parameter matching works "on any tool" for "any scalar parameter the
    # tool accepts" -- open-ended by construction -- and "the value supports `*`
    # as a wildcard that matches any sequence of characters". A hardcoded
    # allowlist could only ever chase that: it exempted WebFetch/domain and then
    # flagged `Agent(model:*-haiku)`, a documented parameter form whose wildcard
    # happens to land mid-value.
    #
    # So: in a deny or ask rule, an `identifier:value` body IS the parameter
    # form and the mid-pattern rule does not apply to it. In an allow rule it
    # cannot be the parameter form at all -- an allow rule uses the specifier
    # syntax its own tool defines -- so a command-prefix reading is the only one
    # and the check still applies.
    # ...and the value must carry NO SPACE. "Each rule names one parameter" and
    # its value is a single scalar, so a parameter value never has
    # space-separated trailing words -- while the dead form is precisely a
    # command prefix FOLLOWED BY MORE WORDS.
    #
    # Without this, `git` parses as an identifier and `deny Bash(git:* push)` --
    # the OWN dead-rule example the page gives -- went silent. That is worse
    # than the false positive it replaced: a dead ALLOW fails closed (the
    # operator is denied something they thought they had), a dead DENY fails
    # OPEN (they believe they blocked `git push` and did not). The space is a
    # property of the grammar, so it does not reintroduce the name allowlist.
    #
    # In an ALLOW rule the same shape is exempted for a different reason: it is
    # already reported by C6-allowParam, which explains it correctly (an allow
    # rule cannot use the parameter form at all). Letting colonStar fire too
    # gave one rule two findings with two mechanics, and for a tool that takes
    # no command prefixes -- `Agent` -- the colonStar explanation is simply
    # wrong. The rule is dead either way; only one of the two says why.
    cs = index(body, ":*")
    is_param_shape = (prefix_of(body) ~ /^[A-Za-z_][A-Za-z0-9_]*$/) && (value_of(body) !~ /[ \t]/)
    param_form = (kind != "allow") ? is_param_shape \
      : (is_param_shape && (tool SUBSEP prefix_of(body)) in param_only)
    if (cs > 0 && cs + 1 < length(body) && !param_form && !((tool SUBSEP prefix_of(body)) in documented_param))
      finding("error", "C6-colonStar", scope, text " — the :* form is only recognized at the END of a pattern; here the colon is treated as a literal character and the rule will not match what it looks like it matches")
    # Mid-pattern `:*` with no trailing space is structurally identical to a live
    # parameter form (`Agent(model:*-haiku)`). Once the space is gone nothing in
    # the rule text distinguishes them; silence is fail-open on deny/ask rules.
    if (cs > 0 && cs + 1 < length(body) && kind != "allow" && is_param_shape && !((tool SUBSEP prefix_of(body)) in documented_param) && !((tool SUBSEP prefix_of(body)) in param_only))
      finding("warning", "C6-colonStarAmbiguous", scope, text " — mid-pattern :* with no trailing space is indistinguishable from a documented parameter form; this rule may be a dead command prefix or a parameter wildcard — verify which you intended")

    # Parameter form is `Tool(param:value)`. Two distinct defects live here.
    colon = index(body, ":")
    if (colon > 1) {
      param = substr(body, 1, colon - 1)
      sub(/[ \t]+$/, "", param)
      if (tool in content_field && param == content_field[tool])
        finding("error", "C6-contentField", scope, text " — a rule cannot match a tool primary content field by parameter (" tool " uses " content_field[tool] "); Claude Code ignores this rule and warns at startup")
      # "Deny and ask rules can match a top-level input parameter… An allow rule
      # for one parameter value would not establish that the call is safe
      # overall, so allow rules continue to use the syntax each tool defines
      # syntax." So parameter form in an ALLOW rule is not a grant at all --
      # the operator believes they narrowed a permission and did not.
      #
      # A per-tool specifier syntax uses the same `word:` shape for some
      # tools (`WebFetch(domain:host)` is documented as the WebFetch form, and
      # `Bash(npm:*)` is a command prefix), so this fires only where the shape
      # is unambiguously the parameter form: a known top-level parameter name
      # on a tool whose own syntax is a path or a command.
      else if (kind == "allow" && (tool SUBSEP param) in param_only)
        finding("warning", "C6-allowParam", scope, text " — parameter matching is documented for deny and ask rules only; an allow rule uses the specifier syntax its own tool defines, so this grant may not take effect as written")
    }

    # A path-shaped rule on a tool whose path rules are never consulted. Only
    # allow/deny path shapes are relevant, and only when the body actually looks
    # like a path rather than a parameter form.
    if (tool in uncovered && colon == 0)
      finding("warning", "C6-uncoveredPath", scope, text " — file permissions are checked against Edit(path) and Read(path) rules only, so a path rule for " tool " is accepted but never consulted (warns at startup, v2.1.210+; a Glob rule passed in --allowedTools is the documented exception)")
  }

  print "lint summary findings=" n_findings + 0 " checks_run=9"
}
')" || {
  echo "ERROR: no scope records on input — permission-plane-lint.sh will not report a clean plane it never read" >&2
  exit 2
}

printf '%s\n' "$lint_out"
