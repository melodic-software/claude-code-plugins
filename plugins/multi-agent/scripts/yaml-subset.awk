# Flatten the multi-agent YAML subset to `dotted.key<TAB>value` records.
#
# The subset: nested mappings by indentation, scalar values, `#` comments
# (whole-line, or after whitespace), optional single or double quotes around a
# value. No lists, anchors, multi-line scalars or flow collections.
#
# -v BLOCK=1 reads only the lines inside the first ```yaml config fence (a
# docs convention file); line numbers still name the .md file's own lines.
# On a parse error prints `error<TAB><line><TAB><message>` and exits 1.
# Prints `block<TAB>1` first when BLOCK=1 found a fence.

function fail(msg) {
  print "error\t" NR "\t" msg
  failed = 1
  exit 1
}

BEGIN { n = 0; lastind = 0; opened = 0; inblock = (BLOCK == 1) ? 0 : 1; seen = 0 }

{
  sub(/\r$/, "")
  if (NR == 1) sub(/^\357\273\277/, "")
  line = $0
  if (BLOCK == 1) {
    if (!inblock) {
      # Any other fenced block is skipped whole, so a prose example of the
      # config block inside a longer outer fence never counts.
      if (other != "") {
        if (line ~ /^`+[ \t]*$/ && match(line, /^`+/) && RLENGTH >= length(other)) other = ""
        next
      }
      if (line ~ /^```yaml[ \t]+config[ \t]*$/) {
        if (seen) fail("a second ```yaml config block (the first opens at line " first "); one file holds one")
        inblock = 1; seen = 1; first = NR; print "block\t1"
      } else if (match(line, /^```+/)) {
        other = substr(line, 1, RLENGTH)
      }
      next
    }
    if (line ~ /^```[ \t]*$/) { inblock = 0; done = 1; next }
  }
  if (line ~ /^[ \t]*(#.*)?$/) next
  if (line ~ /^ *\t/) fail("tab indentation")
  match(line, /^ */)
  ind = RLENGTH
  rest = substr(line, ind + 1)
  if (rest ~ /^-( |$)/) fail("lists are not part of the subset")
  if (!match(rest, /^[A-Za-z0-9_-]+:/)) fail("expected `key: value`")
  key = substr(rest, 1, RLENGTH - 1)
  val = substr(rest, RLENGTH + 1)
  if (val != "" && val !~ /^[ \t]/) fail("expected a space after `" key ":`")
  sub(/[ \t]+#.*$/, "", val)
  gsub(/^[ \t]+|[ \t]+$/, "", val)
  if (val ~ /^".*"$/ || val ~ /^'.*'$/) val = substr(val, 2, length(val) - 2)
  else if (val ~ /^[\[{&*|>]/) fail("flow, anchor and block scalars are not part of the subset")
  if (ind > lastind && !opened) fail("unexpected indentation")
  while (n > 0 && ind <= inds[n]) n--
  path = (n > 0 ? paths[n] "." : "") key
  lastind = ind
  opened = (val == "")
  if (opened) { n++; inds[n] = ind; paths[n] = path }
  else print path "\t" val
}

END {
  if (failed) exit 1
  if (BLOCK == 1 && inblock && !done) { print "error\t" NR "\tunclosed ```yaml config fence"; exit 1 }
}
