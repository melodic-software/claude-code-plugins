# root-scopes.jq: turn a resolved configuration's file_names.roots into scope
# entries, so the audit inventory and the emitted gate read one definition of
# what a root claims.
#
#   jq -f root-scopes.jq <resolved configuration>
#
# A root is a string (a path whose every tracked file is in scope) or an object
# `{"path", "extensions", "exempt_paths"}`: `extensions` limits the root to
# those file extensions, matched in any case, and `exempt_paths` holds git glob
# pathspecs, relative to the repository root, that this root never judges by
# basename. A path another root claims without exempting it is still judged,
# and the case-collision check covers every path any root claims.
#
# Output: one array, one entry per root, each carrying
#   specs       git pathspecs naming the files the root claims
#   exempt      the root's exempt_paths, as given
#   label       a one-line form for a report line: `docs`, `. (*.md)`
#   rule_paths  the globs a path-scoped rule file lists for the root

# `md` becomes `[mM][dD]`: git's glob magic has no case-folding of its own that
# would spare the root's path prefix.
def any_case:
  ascii_downcase | split("")
  | map(if test("^[a-z]$") then "[" + . + ascii_upcase + "]" else . end)
  | join("");

[
  .file_names.roots[]
  | (if type == "string" then {path: ., extensions: [], exempt_paths: []}
     else {path: .path, extensions: (.extensions // []), exempt_paths: (.exempt_paths // [])}
     end) as $r
  | ($r.path | rtrimstr("/") | if . == "." or . == "" then "" else . + "/" end) as $prefix
  | {
      path: $r.path,
      extensions: $r.extensions,
      exempt: $r.exempt_paths,
      specs: (if ($r.extensions | length) == 0 then [":(glob)" + $prefix + "**"]
              else $r.extensions | map(":(glob)" + $prefix + "**/*." + any_case) end),
      label: (if ($r.extensions | length) == 0 then $r.path
              else $r.path + " (" + ($r.extensions | map("*." + ascii_downcase) | join(", ")) + ")" end),
      rule_paths: (if ($r.extensions | length) == 0 then [$prefix + "**"]
                   else $r.extensions | map($prefix + "**/*." + ascii_downcase) end)
    }
]
