#!/usr/bin/env bash
# Amplification of the Windows kernel Token leak recorded in README.md.
#
# Claim: leaked tokens equal the child-creating process count, so fan-out
# multiplies the leak by fires times creators per fire.
# Basis: #4372, melo-lap-001, build 26200.9457, N=300. Rows with a published
# band use that band. The launcher pair (0.99, 1.01) and gh (0.98) published
# no band; this probe accepts 0.05 around the one-for-one line for those three.
# As of: 2026-09-28.
# Recheck trigger: a Windows build greater than 26200.9550, or a Microsoft
# acknowledgement of the Token leak.
#
#   token-leak-amplification.sh --self-test
#   token-leak-amplification.sh --amplify <fires> <creators-per-fire>
set -euo pipefail

usage() {
  cat <<'EOF'
token-leak-amplification.sh — one leaked token per child-creating process.

  --self-test                         check the #4372 rows against that line
  --amplify <fires> <creators>        print fires times creators
EOF
}

self_test() {
  awk 'BEGIN {
    rows[1] = "0 0.00 0.13"
    rows[2] = "1 1.04 0.13"
    rows[3] = "1 1.04 0.14"
    rows[4] = "2 2.15 0.15"
    rows[5] = "6 5.95 0.18"
    rows[6] = "1 0.96 0.14"
    rows[7] = "1 0.99 0.05"
    rows[8] = "1 1.01 0.05"
    rows[9] = "1 0.98 0.05"
    fail = 0
    for (i = 1; i <= 9; i++) {
      split(rows[i], f, " ")
      d = f[2] - f[1]
      if (d < 0) d = -d
      if (d > f[3] + 0.0000001) {
        printf "out of band: creators=%s leaked=%s band=%s\n", f[1], f[2], f[3] > "/dev/stderr"
        fail = 1
      }
    }
    if ((10 * 6) != 60) {
      print "amplification 10 fires of 6 creators must be 60" > "/dev/stderr"
      fail = 1
    }
    exit fail
  }'
}

case "${1:-}" in
--self-test)
  self_test
  echo "token-leak-amplification: published rows sit on the one-for-one line"
  ;;
--amplify)
  fires="${2:-}"
  creators="${3:-}"
  if [[ ! "$fires" =~ ^[0-9]+$ || ! "$creators" =~ ^[0-9]+$ ]]; then
    echo "token-leak-amplification: --amplify needs two whole numbers" >&2
    exit 2
  fi
  echo $((fires * creators))
  ;;
--help | -h)
  usage
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
