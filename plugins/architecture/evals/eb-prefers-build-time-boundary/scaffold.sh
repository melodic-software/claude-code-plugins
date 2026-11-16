#!/usr/bin/env bash
# A Go module where billing keeps its ledger in the subpackage billing/ledger, reporting imports
# only package billing, and the topic doc records an entry-points-only rule for billing. The
# checks run through scripts/check.sh (go vet and go test). No Go toolchain is needed: the case
# asks for the plan only.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs go.mod billing reporting scripts
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh"

cat >>docs/conventions/architecture/README.md <<'MD'

## Boundary rules

- Other packages reach billing only through package billing; billing/ledger is billing's own, and no package outside billing imports it, tests included. Evidence: billing/billing.go:3, reporting/report.go:3. Accepted 2026-10-30.
MD

mkdir -p billing/ledger reporting scripts

cat >go.mod <<'GO'
module example.com/shop

go 1.22
GO

cat >billing/ledger/ledger.go <<'GO'
package ledger

type Entry struct {
	Account string
	Cents   int64
}

func Balance(entries []Entry) int64 {
	var total int64
	for _, e := range entries {
		total += e.Cents
	}
	return total
}
GO

cat >billing/billing.go <<'GO'
package billing

import "example.com/shop/billing/ledger"

func Outstanding(entries []ledger.Entry) int64 {
	return ledger.Balance(entries)
}
GO

cat >reporting/report.go <<'GO'
package reporting

import "example.com/shop/billing"

func Total(entries [][]int64) int64 {
	_ = billing.Outstanding
	return 0
}
GO

cat >scripts/check.sh <<'SH'
#!/usr/bin/env bash
# Runs every check this repository has. CI runs this file.
set -euo pipefail
go vet ./...
go test ./...
SH

git add -A
git commit -q -m "Billing with a ledger subpackage, and reporting"
