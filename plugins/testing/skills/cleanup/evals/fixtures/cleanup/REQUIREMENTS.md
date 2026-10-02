# Shop pricing requirements

The fixture's stated contract, the independent source a rewrite takes its expected values from.

1. Every price includes 20% sales tax.
2. An order line above 100 gets a 10% discount, applied before tax.
3. Prices are rounded to 2 decimal places.

Worked examples:

| Amount | Price |
|---|---|
| 50 | 60.00 |
| 150 | 162.00 |

Shipping fees are set per handler and are not specified here.
