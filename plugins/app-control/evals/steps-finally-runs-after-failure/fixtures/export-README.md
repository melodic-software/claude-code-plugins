# Export invoices

A user downloads their invoices as one CSV file.

## Parts

- content: the file holds a row for each invoice, including one just created

## Sub-features

none

## Entry points

- the `Export` button on the billing page: driven

## Reset

The finally steps from [reset.yaml](reset.yaml) delete the test invoice the drive creates.

## Drive

Run the steps in [steps.yaml](steps.yaml): create a test invoice, export, check the file holds it.

## Gotchas

- The test invoice is the only row with amount 1.00; reset deletes it by that amount.
