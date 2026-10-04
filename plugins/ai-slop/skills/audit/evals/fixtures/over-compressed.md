# Deploying the reporting service

Build image, push to registry, bump tag in values file. Deploy w/ helm upgrade, wait
for rollout.

If pods crashloop → check cfg secret, likely missing DB url. Rollback = previous tag,
helm upgrade again.

The service reads its database URL from the `REPORTS_DB_URL` environment variable,
which the chart fills in from the `reports-db` secret.
