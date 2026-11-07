#!/usr/bin/env bash
# A Go module with an interval Merge function, rapid already required for property tests, and no
# test for Merge.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main go.mod intervals
mkdir -p intervals
cat >go.mod <<'EOF'
module example.com/schedule

go 1.25

require pgregory.net/rapid v1.2.0
EOF
cat >intervals/merge.go <<'EOF'
package intervals

import "sort"

// Interval is a half-open range [Start, End).
type Interval struct{ Start, End int }

// Merge combines two interval lists into one sorted list with overlapping intervals joined.
func Merge(a, b []Interval) []Interval {
  all := append(append([]Interval{}, a...), b...)
  sort.Slice(all, func(i, j int) bool { return all[i].Start < all[j].Start })
  var out []Interval
  for _, iv := range all {
    if n := len(out); n > 0 && iv.Start <= out[n-1].End {
      if iv.End > out[n-1].End {
        out[n-1].End = iv.End
      }
      continue
    }
    out = append(out, iv)
  }
  return out
}
EOF
g add -A
g commit -q -m "interval merge"
