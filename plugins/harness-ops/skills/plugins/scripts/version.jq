def version_triple:
  if type == "string" then
    ((capture("^v?(?<maj>[0-9]+)[.](?<min>[0-9]+)[.](?<pat>[0-9]+)") // null)
     | if . == null then null else [.maj, .min, .pat] | map(tonumber) end)
  else null end;

def version_direction($old; $new):
  ($old | version_triple) as $o | ($new | version_triple) as $n
  | if $o == null or $n == null then "unknown"
    elif $n > $o then "forward"
    elif $n < $o then "backward"
    elif $old == $new then "same"
    else "unknown" end;
