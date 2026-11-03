#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p app/billing-worker app/admin-api app/export-job app/cli config
cat >app/billing-worker/settle.sql <<'EOF'
UPDATE invoices SET status = 'paid' WHERE id = :invoice_id;
EOF
cat >app/admin-api/void-invoice.sql <<'EOF'
UPDATE invoices SET status = 'void' WHERE id = :invoice_id;
EOF
cat >app/export-job/nightly.sh <<'EOF'
#!/usr/bin/env bash
printf 'export_path=%s\n' "/var/exports/$(date +%F)" >config/export-path.conf
EOF
cat >app/cli/setup.sh <<'EOF'
#!/usr/bin/env bash
printf 'export_path=%s\n' "${1:-/var/exports}" >config/export-path.conf
EOF
printf 'export_path=/var/exports\n' >config/export-path.conf
git add . && git commit -q -m "feat: add the billing worker, admin API, export job and CLI setup"
