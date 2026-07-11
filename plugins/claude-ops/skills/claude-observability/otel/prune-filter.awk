# prune-filter.awk — route OTEL store lines by age (kept / dropped / surgery).
# Invoked via: awk -v cutoff=... -v body_cutoff=... -v dst=... -v ddst=... -v sdst=... -v tf=... -f prune-filter.awk <src>
#
#   older than the structure cutoff          -> ddst (whole-line drop; compacts to cold)
#   else body-class AND older than body cutoff -> sdst (jq strips api_*_body records)
#   else                                     -> dst, verbatim
# Prints "kept=<n> dropped=<n> total=<n> surgery=<n> body_dropped=<n> would_compact=<n>".

function is_body(line) {
  return index(line, "\"key\":\"event.name\",\"value\":{\"stringValue\":\"api_request_body\"}") \
    || index(line, "\"key\":\"event.name\",\"value\":{\"stringValue\":\"api_response_body\"}")
}
function prefix_len() { return length(tf) + 4 }
{ total++ }
match($0, "\"" tf "\":\"[0-9]+\"") {
  pl = prefix_len()
  ns = substr($0, RSTART + pl, RLENGTH - pl - 1)
  secs = substr(ns, 1, length(ns) - 9)
  if (secs + 0 < cutoff + 0) {
    would_compact++
    if (is_body($0)) body_dropped++
    if (ddst != "") print $0 > ddst
  } else if (secs + 0 < body_cutoff + 0 && is_body($0)) {
    surgery++
    if (sdst != "") print $0 > sdst
  } else {
    kept++
    if (dst != "") print $0 > dst
  }
}
END {
  printf "kept=%d dropped=%d total=%d surgery=%d body_dropped=%d would_compact=%d\n", \
    kept, total - kept - surgery, total, surgery, body_dropped, would_compact
}
