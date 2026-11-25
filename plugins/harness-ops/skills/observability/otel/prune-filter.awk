function is_body(line) {
  return index(line, "\"key\":\"event.name\",\"value\":{\"stringValue\":\"api_request_body\"}") \
    || index(line, "\"key\":\"event.name\",\"value\":{\"stringValue\":\"api_response_body\"}")
}
BEGIN { prefix_len = length(tf) + 4 }
{ total++ }
match($0, "\"" tf "\":\"[0-9]+\"") {
  ns = substr($0, RSTART + prefix_len, RLENGTH - prefix_len - 1)
  secs = substr(ns, 1, length(ns) - 9) + 0
  if (secs < cutoff + 0) {
    would_compact++
    if (is_body($0)) body_dropped++
    if (ddst != "") print $0 > ddst
  } else if (secs < body_cutoff + 0 && is_body($0)) {
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
