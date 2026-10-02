#!/usr/bin/env bash
# order_total_cents <amount>: the amount plus 20% tax, in cents.
order_total_cents() {
  local cents=$(($1 * 100))
  echo $((cents * 12 / 10))
}
