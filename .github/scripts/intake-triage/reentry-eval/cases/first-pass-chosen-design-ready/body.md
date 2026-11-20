## Problem

The plugin index page lists each plugin as a plain text row, so a reader cannot tell where one
plugin's entry ends and the next begins.

## Requested behavior

Show each plugin as a card, in the design picked at the last design review (no other layout is
in scope):

- a 1px `#d0d7de` border, a 6px corner radius and 16px padding;
- the plugin name in 16px semibold, with its one-line description below it in 14px regular;
- three cards per row at viewport widths of 1012px and above, one card per row below that.

## Done when

- [ ] The plugin index page shows each plugin as a card with exactly the border, radius, padding and
  type sizes above.
- [ ] At 1280px wide the page shows three cards per row; at 600px wide it shows one.
