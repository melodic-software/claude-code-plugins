# Export invoices

A user downloads their invoices as one CSV file.

## Parts

- content: the file holds a row for each invoice in the month the filter shows

## Sub-features

none

## Entry points

- the `Export` button on the billing page: driven

## Reset

The finally steps from [reset.yaml](reset.yaml) clear the month filter the drive sets.

## Drive

Run the steps in [steps.yaml](steps.yaml): set the month filter, export, check the file holds only that month.

## Gotchas

- The month filter stays set for the browser session until it is cleared, so a later feature would see it.
