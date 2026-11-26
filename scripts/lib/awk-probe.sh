#!/usr/bin/env bash
awk_probe::banner() {
  local cmd="$1" line
  line="$("$cmd" --version 2>/dev/null </dev/null | sed -n 1p)"
  [[ -n "$line" ]] || line="$("$cmd" -W version 2>/dev/null </dev/null | sed -n 1p)"
  printf '%s' "$line"
}

awk_probe::run() {
  local candidates="${SHELL_PORTABILITY_AWKS:-gawk mawk nawk original-awk bwk-awk}"
  local -a impls=() names=()
  local -A seen=()
  local cand path banner
  for cand in $candidates; do
    path="$(command -v "$cand" 2>/dev/null)" || continue
    [[ "$path" == /* ]] || continue
    banner="$(awk_probe::banner "$path")"
    [[ -n "$banner" ]] || banner="$path"
    [[ -n "${seen[$banner]+set}" ]] && continue
    seen[$banner]=1
    impls+=("$path")
    names+=("$cand")
  done
  if ((${#impls[@]} < 2)); then
    printf 'Error: --awk-probe needs two distinct awk implementations on PATH; found %d (%s) from: %s\n' \
      "${#impls[@]}" "${names[*]:-none}" "$candidates" >&2
    return 2
  fi

  local suite
  for suite in "$@"; do
    if [[ ! -f "$suite" ]]; then
      printf 'Error: no such suite: %s\n' "$suite" >&2
      return 2
    fi
  done

  local work
  work="$(mktemp -d)" || return 2
  local i
  for i in "${!impls[@]}"; do
    if ! { mkdir -p "$work/shim$i" && ln -s "${impls[$i]}" "$work/shim$i/awk"; }; then
      rm -rf "$work"
      return 2
    fi
  done

  printf 'awk-probe: %s\n' "${names[*]}"
  local divergent=0 report verdict n
  local -a rcs=()
  for suite in "$@"; do
    report="" verdict="agree" n=0 rcs=()
    for i in "${!impls[@]}"; do
      PATH="$work/shim$i:$PATH" bash "$suite" >"$work/out$i" 2>&1
      rcs[i]=$?
      report+=" ${names[$i]}=${rcs[i]}"
      ((rcs[i] == rcs[0])) || verdict="DIVERGENT"
      ((rcs[i] == 0)) || n=$((n + 1))
    done
    if [[ "$verdict" == "DIVERGENT" ]]; then
      divergent=1
      printf 'DIVERGENT: %s:%s\n' "$suite" "$report"
      for i in "${!impls[@]}"; do
        ((rcs[i] == 0)) && continue
        printf -- '--- %s under %s (last 5 lines):\n' "$suite" "${names[$i]}"
        tail -n 5 "$work/out$i"
      done
    elif ((n > 0)); then
      printf 'FAILS UNDER EVERY AWK (not a divergence): %s:%s\n' "$suite" "$report"
    else
      printf 'ok: %s:%s\n' "$suite" "$report"
    fi
  done
  rm -rf "$work"

  if ((divergent)); then
    cat >&2 <<'EOF'

A suite that passes under one awk and fails under another usually hands a
value to awk with `-v name="$shellvar"`. `-v` runs escape processing on the
value, and implementations disagree on an unknown escape: a regex such as
`\]\([^)]*$` reaches gawk as `]([^)]*$`. Pass the value through the
environment instead, which every awk reads byte for byte:

  NAME="$shellvar" awk '... ENVIRON["NAME"] ...'

Other causes are an implementation-only builtin or ERE syntax the other awk
lacks; the output tail above names the line.
EOF
    return 1
  fi
  return 0
}
