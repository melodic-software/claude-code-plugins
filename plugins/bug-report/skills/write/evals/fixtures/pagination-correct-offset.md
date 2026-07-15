# Fixture — pagination helper (math is correct)

Source under discussion: `apps/reports/src/paginate.js`

```javascript
// Returns the slice of `items` for a 1-based page number.
// page 1 => items[0 .. pageSize-1], page 2 => items[pageSize .. 2*pageSize-1], ...
export function paginate(items, page, pageSize) {
  const start = (page - 1) * pageSize;
  return items.slice(start, start + pageSize);
}
```

There is exactly one `paginate` in the repo (this file). No recent changes: `git log` shows the last edit was 6 weeks ago, "feat: add report pagination".

Reporter's claim: "page 2 skips the last row that should have been on page 1 — it's off by one."

Worked check (what a survey + run would show):

- 10 items, `pageSize = 4`.
- `paginate(items, 1, 4)` -> `items.slice(0, 4)` -> rows 0,1,2,3.
- `paginate(items, 2, 4)` -> `items.slice(4, 8)` -> rows 4,5,6,7.
- No row is skipped and none is duplicated; page 1 ends at index 3, page 2 begins at index 4. The 1-based-to-0-based conversion `(page - 1) * pageSize` is correct.

The reporter appears to have mentally used a 0-based page number (`page 2 => start at index 8`), which the function's documented 1-based contract does not use.
