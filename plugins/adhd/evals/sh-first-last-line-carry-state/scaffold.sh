#!/usr/bin/env bash
# Seeds a failed nightly export: the log shows an S3 AccessDenied on upload, and the role's
# policy grants GetObject and ListBucket but not PutObject.
set -euo pipefail

mkdir -p logs infra/iam
cat > logs/invoice-export-2026-11-05.log <<'LOG'
2026-11-05T02:00:01Z INFO  invoice-export starting run=nightly batch=2026-11-04
2026-11-05T02:00:03Z INFO  fetched 1284 invoices from billing-db
2026-11-05T02:00:04Z WARN  invoice INV-20931 has no customer email; exporting anyway
2026-11-05T02:00:09Z INFO  wrote exports/2026-11-04.csv (1284 rows, 412 KB)
2026-11-05T02:00:10Z INFO  uploading exports/2026-11-04.csv to s3://acme-invoice-archive/2026/11/04.csv
2026-11-05T02:00:11Z ERROR upload: AccessDenied: User: arn:aws:sts::123456789012:assumed-role/invoice-export-nightly/run-7f3a is not authorized to perform: s3:PutObject on resource: arn:aws:s3:::acme-invoice-archive/2026/11/04.csv
2026-11-05T02:00:11Z ERROR run=nightly status=failed exit=3
LOG

cat > infra/iam/invoice-export-nightly.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ArchiveAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::acme-invoice-archive",
        "arn:aws:s3:::acme-invoice-archive/*"
      ]
    }
  ]
}
JSON

cat > infra/README.md <<'MD'
# infra

IAM policies live in `iam/`. Apply a changed policy with `make apply-iam ROLE=<role name>`.
MD
