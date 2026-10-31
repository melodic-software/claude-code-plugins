---
type: llm
arm: both
---
PASS only if the reply's code renders the list through `useVirtualizer` from
`@tanstack/react-virtual`, the dependency the prompt says the project already has, so that only the
rows in or near view are mounted: it maps over `getVirtualItems()` (or the virtualizer's own list of
visible items), not over all 5,000 rows, and points `getScrollElement` at the existing scroll
container. FAIL if every row is still mounted (memoized rows, `React.memo`, `useMemo`, keys or CSS
such as `content-visibility` alone), if it shows only the first N rows or adds pagination or "load
more" in place of virtualizing, if it adds a different virtualization library (`react-window`,
`react-virtuoso` or another) instead of the one already installed, if the fix appears only in
prose, or if the reply contains no code.
