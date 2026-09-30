# Diff kinds shared by the readers: containers added or removed, image,
# replicas, ports, network and Ingress nodes, parameter presence, plain
# parameter values, and secret parameters. A reader fills the global arrays
# image[env,container], replica_of[env,container] ("undeclared" is never
# compared), node_seen[env,kind,name] (kind
# network or ingress, value the node detail), placed[env,container], portjoin[env,container],
# param_seen[env,container,name], plain_val[...] and secret_val[...] (same key
# as param_seen), and defines jesc() and the diffs output file. A secret value
# is compared here and never printed.
function emit_diff(change, a, b, tool, c, detail) {
  printf "{\"change\":\"%s\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"%s\",\"container\":\"%s\",\"detail\":\"%s\"}\n", \
    change, jesc(a), jesc(b), tool, jesc(c), jesc(detail) >> diffs
}
function container_diffs(a, b, tool,    sk, sp, c, ra, rb) {
  for (sk in image) {
    split(sk, sp, SUBSEP)
    c = sp[2]
    if ((a SUBSEP c) in image && !((b SUBSEP c) in image))
      emit_diff("removed", a, b, tool, c, "present only in " a)
    else if ((b SUBSEP c) in image && !((a SUBSEP c) in image))
      emit_diff("added", a, b, tool, c, "present only in " b)
    else if ((a SUBSEP c) in image && (b SUBSEP c) in image && image[a SUBSEP c] != image[b SUBSEP c])
      emit_diff("image", a, b, tool, c, image[a SUBSEP c] " -> " image[b SUBSEP c])
  }
  for (sk in replica_of) {
    split(sk, sp, SUBSEP)
    c = sp[2]
    ra = replica_of[a SUBSEP c]; rb = replica_of[b SUBSEP c]
    if ((a SUBSEP c) in replica_of && (b SUBSEP c) in replica_of && ra != rb && ra != "undeclared" && rb != "undeclared")
      emit_diff("replicas", a, b, tool, c, ra " -> " rb)
  }
}
function param_port_diffs(a, b, tool,   sk, sp, c, k, ka, kb, pa, pb, sa, sb, ea, eb) {
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
function node_diffs(a, b, tool,    sk, sp, k, n, ea, eb) {
  for (sk in node_seen) {
    split(sk, sp, SUBSEP)
    if (sp[1] != a && sp[1] != b) continue
    k = sp[2]; n = sp[3]
    ea = a SUBSEP k SUBSEP n
    eb = b SUBSEP k SUBSEP n
    if ((ea in node_seen) && !(eb in node_seen))
      emit_diff(k "-removed", a, b, tool, n, k " present only in " a)
    else if ((eb in node_seen) && !(ea in node_seen))
      emit_diff(k "-added", a, b, tool, n, k " present only in " b)
    else if (node_seen[ea] != node_seen[eb])
      emit_diff(k, a, b, tool, n, node_seen[ea] " -> " node_seen[eb])
  }
}
