# Export invoices

A user downloads their invoices as one CSV file.

## Parts

- range: the download covers the chosen date range

## Sub-features

none

## Entry points

- the `Export` button on the billing page: driven
- `GET /api/invoices.csv`: not driven

## Reset

Delete `shop/data/invoices.db` and restart the app.

## Drive

- Open `/billing`, choose `Export`; a file named `invoices.csv` downloads.

## Gotchas

- An empty month downloads a header-only file.
