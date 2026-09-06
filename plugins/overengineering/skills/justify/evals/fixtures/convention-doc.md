# Naming convention for background jobs

A job class is named for the work it does, not for when it runs. `ReconcileInvoices`, never
`NightlyJob`. A schedule changes; the work does not.

## Queue names

Queue names are lowercase and hyphenated, and carry the priority as a suffix: `invoices-high`,
`invoices-default`. A job with no explicit queue goes to `default`.

## Retries

State the retry count on the class. A job that must not be retried says so explicitly rather than
relying on the framework default, because the default has changed twice.

## Where this applies

Everything under the jobs directory. Nothing else in the tree has jobs in it.
