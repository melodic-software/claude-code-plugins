# Export invoices

A user downloads the invoices for a range of months as one CSV file.

## Parts

- range: the download covers the months chosen as start and end

## Sub-features

none

## Entry points

- the `Export` button on the billing page: driven

## Reset

Delete `shop/data/invoices.db` and restart the app.

## Drive

Run the steps in [steps.yaml](steps.yaml): open the billing page, pick the start month, pick the
end month, then press Export.

## Gotchas

- The month picker shows the current month until a month is chosen.
