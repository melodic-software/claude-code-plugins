# Export invoices

A user downloads their invoices as one CSV file.

## Parts

- download: the file is named invoices.csv

## Sub-features

none

## Entry points

- the `Export` button on the billing page: driven

## Reset

Delete `shop/data/invoices.db` and restart the app.

## Drive

Run the steps in `steps.yaml`: open the billing page, accept the cookie banner when it
shows, press Export, check the download.

## Gotchas

- The cookie banner shows on the first visit of a browser profile only.
