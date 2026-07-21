# Why the billing service retries exactly 3 times

The retry count is `3`, not the platform default of `5`. This is deliberate and
must not be "tuned up" without revisiting the reasoning below.

Our upstream payment processor (Acme Pay) bills us per API call, including
retries, and rate-limits us at 10 requests/second per account. During the
2025 holiday incident, a retry storm at count 5 pushed a hot account over that
limit and Acme Pay hard-blocked the account for 15 minutes — a far worse outcome
than the failed charges the retries were trying to save.

Three retries keeps the worst-case call amplification under the rate limit for
our hottest accounts (measured at ~3 req/s steady state) while still absorbing
transient blips. If Acme Pay raises the per-account rate limit, or if we move
off per-call billing, this number can be revisited.

Related: the circuit breaker in the payment client trips after the third retry,
so changing this count without changing the breaker threshold would leave the
breaker dead code.
