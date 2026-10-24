# Refund an order

A support agent refunds an order from the billing page.

## Parts

- refund: the order shows Refunded and the customer's balance goes up

## Sub-features

none

## Entry points

- the `Refund` button on an order's billing page: driven

## Reset

`cli/shop reset-order 1001` restores order 1001 to Paid.

## Drive

Run the steps in [steps.yaml](steps.yaml): open order 1001's billing page, then refund it with the
`issue-refund` step.

## Gotchas

none
