# Diff kinds shared by the Compose and Kubernetes readers: ports, parameter
# presence, plain parameter values, and secret parameters. A reader fills the
# global arrays placed[env,container], portjoin[env,container],
# param_seen[env,container,name], plain_val[...] and secret_val[...] (same key
# as param_seen), and defines jesc() and the diffs output file. A secret value
# is compared here and never printed.
function emit_diff(change, a, b, tool, c, detail) {
  printf "{\"change\":\"%s\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"%s\",\"container\":\"%s\",\"detail\":\"%s\"}\n", \
    change, jesc(a), jesc(b), tool, jesc(c), jesc(detail) >> diffs
}
function param_port_diffs(a, b, tool,    sk, sp, c, k, ka, kb, pa, pb, sa, sb, ea, eb) {
  for (sk in placed) {
    split(sk, sp, SUBSEP)
    if (sp[1] != a || !((b SUBSEP sp[2]) in placed)) continue
    c = sp[2]
    pa = portjoin[a SUBSEP c]; if (pa == "") pa = "none"
    pb = portjoin[b SUBSEP c]; if (pb == "") pb = "none"
    if (pa != pb) emit_diff("ports", a, b, tool, c, pa " -> " pb)
  }
  for (sk in param_seen) {
    split(sk, sp, SUBSEP)
    c = sp[2]; k = sp[3]
    if ((sp[1] != a && sp[1] != b) || !((a SUBSEP c) in placed) || !((b SUBSEP c) in placed)) continue
    ea = a SUBSEP c SUBSEP k
    eb = b SUBSEP c SUBSEP k
    ka = ea in param_seen
    kb = eb in param_seen
    sa = ea in secret_val
    sb = eb in secret_val
    if (ka && !kb)
      emit_diff("parameter-removed", a, b, tool, c, (sa ? "secret parameter " k : k " " plain_val[ea]) " present only in " a)
    else if (kb && !ka)
      emit_diff("parameter-added", a, b, tool, c, (sb ? "secret parameter " k : k " " plain_val[eb]) " present only in " b)
    else if (sa != sb || (sa && secret_val[ea] != secret_val[eb]))
      emit_diff("secret-differs", a, b, tool, c, "secret parameter " k " differs")
    else if (!sa && plain_val[ea] != plain_val[eb])
      emit_diff("parameter", a, b, tool, c, k " " plain_val[ea] " -> " plain_val[eb])
  }
}
