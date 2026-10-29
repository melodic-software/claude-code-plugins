# Export invoices

A user downloads their invoices as one CSV file.

## Parts

- range: the download covers the chosen date range
- format: the file is comma separated with a header row

## Sub-features

none

## Entry points

- the `Export` button on the billing page: driven
- `GET /api/invoices.csv`: not driven: the endpoint needs an API key this run lacks

## Reset

Delete `shop/data/invoices.db` and restart the app.

## Drive

- Open `/billing`, choose `Export`; a file named `invoices.csv` downloads.

## Gotchas

- The date range defaults to the current month; an empty month downloads a header-only file.
