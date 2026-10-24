# Export invoices

A user downloads their invoices as one CSV file and leaves a note on the export.

## Parts

- download: the file is named invoices.csv
- note: the export history keeps a note the user typed

## Sub-features

none

## Entry points

- the `Export` button on the billing page: driven

## Reset

Delete `shop/data/invoices.db` and restart the app.

## Drive

Run the steps in [steps.yaml](steps.yaml): open the billing page, press Export, check the
download, then add a note to the export history.

## Gotchas

- The note is stored in the shared billing database, not the app's own data.
