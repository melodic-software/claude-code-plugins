function sort_key(v,   core, n, f) {
  core = v
  sub(/[+-].*$/, "", core)
  n = split(core, f, ".")
  return sprintf("%05d.%05d.%05d", f[1] + 0, (n >= 2 ? f[2] + 0 : 0), (n >= 3 ? f[3] + 0 : 0))
}

function finish_file() {
  if (mode == "order" && cur != "") {
    if (dup_list != "") printf "DUP\t%s\t%s\n", cur, dup_list
    if (ord_bad != "") printf "ORD\t%s\t%s\n", cur, ord_bad
  }
  delete seen
  dup_list = ""
  ord_bad = ""
  prev = ""
  prev_key = ""
}

FNR == 1 {
  finish_file()
  cur = FILENAME
  infence = 0
  inhtml = 0
  fchar = ""
  flen = 0
  got = 0
}

mode == "first" && got { next }

{
  if (!infence && inhtml) {
    p = index($0, "-->")
    if (p == 0) next
    inhtml = 0
    rem = substr($0, p + 3)
    while ((q = index(rem, "<!--")) > 0) {
      rem = substr(rem, q + 4)
      r = index(rem, "-->")
      if (r == 0) { inhtml = 1; break }
      rem = substr(rem, r + 3)
    }
    next
  }
  if (match($0, /^ ? ? ?`+/) || match($0, /^ ? ? ?~+/)) {
    seg = substr($0, RSTART, RLENGTH)
    sub(/^ +/, "", seg)
    mchar = substr(seg, 1, 1)
    mlen = length(seg)
    rest = substr($0, RSTART + RLENGTH)
    if (mlen >= 3) {
      if (!infence) {
        if (!(mchar == "`" && rest ~ /`/)) { infence = 1; fchar = mchar; flen = mlen; next }
      } else if (mchar == fchar && mlen >= flen && rest ~ /^[ \t\r]*$/) {
        infence = 0
        next
      }
    }
  }
  if (infence) next
  if (match($0, /^##[ \t]+\[?[0-9]+\.[0-9]+(\.[0-9]+)?([+-][0-9A-Za-z][0-9A-Za-z.-]*)?\]?(\(|$|[ \t\r])/)) {
    h = substr($0, RSTART, RLENGTH)
    if (match(h, /[0-9]+\.[0-9]+(\.[0-9]+)?([+-][0-9A-Za-z][0-9A-Za-z.-]*)?/)) {
      v = substr(h, RSTART, RLENGTH)
      if (mode == "first") {
        printf "%s\t%s\n", FILENAME, v
        got = 1
        next
      }
      if (v in seen) {
        if (seen[v] == 1) dup_list = (dup_list == "" ? v : dup_list " " v)
        seen[v]++
      } else {
        seen[v] = 1
      }
      k = sort_key(v)
      if (ord_bad == "" && prev_key != "" && k > prev_key) {
        ord_bad = v "\t" prev
      }
      prev = v
      prev_key = k
    }
  }
  rem = $0
  while ((q = index(rem, "<!--")) > 0) {
    rem = substr(rem, q + 4)
    r = index(rem, "-->")
    if (r == 0) { inhtml = 1; break }
    rem = substr(rem, r + 3)
  }
}

END { finish_file() }
