// GENERATED from lib/ui-feedback/bar-edges.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
/** Which ends of a sideways-scrolling bar hide tools, from its scrollLeft, scrollWidth and clientWidth; a pixel of slack absorbs fractional scrolling. */
export function edges(scrollLeft, scrollWidth, clientWidth) {
  return { start: scrollLeft > 1, end: scrollLeft + clientWidth < scrollWidth - 1 };
}
