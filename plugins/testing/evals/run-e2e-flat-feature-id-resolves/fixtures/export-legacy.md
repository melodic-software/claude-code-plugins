# Export

A user downloads their invoices.

## Reset

Delete `shop/data/invoices.db` and restart the app.

## States

- empty: the download holds only a header row

## Entry points

- the `Download PDF` link on the billing page
- the `Email invoices` button on the billing page
- `GET /api/invoices.pdf`
- the nightly invoice email

## Drive

- Open `/billing`, choose `Download PDF`.
