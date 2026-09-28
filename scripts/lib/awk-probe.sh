#!/usr/bin/env bash
# awk-probe.sh — the runtime half of the shell-portability gate's `awk -v`
# rule (#4143), sourced by scripts/check-shell-portability.sh for its
# `--awk-probe SUITE...` mode.
#
# POSIX gives an `awk -v name=value` assignment escape processing, and the
# implementations disagree on an escape they do not know: gawk warns and
# drops the backslash, so `\]\([^)]*$` reaches the
# program as `]([^)]*$` and gawk dies on the unmatched paren; mawk passes the
# backslash through and the same script works. `ENVIRON["name"]` carries the
# value byte for byte on every implementation. The dangerous value sits in a
# shell variable, not on the source line, so no token can see it; running the
# suite once per implementation can.
#
# awk_probe::run SUITE... runs each suite with `bash`, once per distinct awk
# implementation, with a shim directory holding an `awk` symlink to that
# implementation placed first on PATH. A suite whose exit status differs across
# implementations is DIVERGENT, and the tail of each failing run's output is
# printed. A suite that fails under every implementation fails for some other
# reason; it is reported and left to the test lanes.
#
# Candidates are SHELL_PORTABILITY_AWKS (space-separated command names; the
# suite overrides it) or gawk, mawk, nawk, original-awk, bwk-awk. Two names can
# be one implementation (Debian's nawk is often gawk), so candidates are
# deduplicated by the first line of their version banner. Fewer than two
# distinct implementations is exit 2: one awk cannot diverge from itself, and a
# probe that silently compared one implementation with itself would report clean.
#
# Residual: a suite that calls an awk by absolute path (`/usr/bin/awk`) or by
# implementation name bypasses the shim.
#
# Exit 0 = no suite diverged; 1 = at least one DIVERGENT suite; 2 = usage /
# environment error (fewer than two implementations, a missing suite).

# awk_probe::banner <cmd> — the first line of an awk's version banner, or
# nothing. gawk and the one-true-awk answer `--version`; mawk answers
# `-W version`.
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
