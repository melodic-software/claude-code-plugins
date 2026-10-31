---
type: llm
arm: both
---
PASS only if the reply's virtualized list keeps the outer scroll container's fixed height and
overflow, makes an inner element as tall as the virtualizer's total size (`getTotalSize()` as its
height, or spacer padding computed from it), and places the visible rows at their offsets in one of
these forms:

- each row absolutely positioned and offset by its virtual item's start (`top: item.start` or a
  `translateY(item.start)` transform), inside an inner element that takes the total size as its
  height and is positioned (`position: 'relative'` or another non-static position, or a Tailwind
  class such as `relative`);
- one wrapper as the inner element's first child, translated by the first visible item's start
  (`translateY(items[0].start)`, or `items[0]?.start ?? 0`), either absolutely positioned at the top
  of a positioned inner element or in normal flow, with the rows in normal flow inside it;
- spacer padding: the rows in normal flow inside the inner element, with space before them equal to
  the first visible item's start and space after them equal to the total size minus the last
  visible item's end (`paddingTop` and `paddingBottom`, or two spacer elements of those heights).

FAIL if the inner element sets the total height but no position while the rows are absolutely
positioned, so they measure from an element outside the scroller; if the rows are positioned with no
offset from their start, or sit in flow with no wrapper offset or spacer before them; if nothing
inside the scroller comes to the total size, so the scrollbar stops at the rendered rows; or if the
reply contains no code.
