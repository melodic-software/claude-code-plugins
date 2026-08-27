// Briefing-header window parsing and rendering.
//
// The `Window:` line in a briefing's header carries two ISO instants joined by
// an arrow. Authors spell that arrow either as a Unicode arrow (`→`) or as the
// ASCII digraph (`->`), so both must parse to the SAME pair of timestamps.

/**
 * A full ISO instant as briefings write it: a calendar date, optionally
 * followed by a time. Anchoring on the `YYYY-MM-DD` shape is what makes the
 * split structurally impossible — a looser class like `[0-9T:Z-]+` lets the
 * engine backtrack and satisfy the first group with just `2026`, leaving the
 * `-` of `04-24` to serve as the separator (#3364).
 */
const ISO_INSTANT = "\\d{4}-\\d{2}-\\d{2}(?:T\\d{2}:\\d{2}(?::\\d{2})?(?:Z|[+-]\\d{2}:?\\d{2})?)?";

/**
 * Separator spellings, longest first so `->` is never consumed as a bare `-`
 * that then strands the `>`.
 */
const SEPARATOR = "(?:-+>|→|[–—]|-)";

const WINDOW_RANGE = new RegExp(`(${ISO_INSTANT})\\s*${SEPARATOR}\\s*(${ISO_INSTANT})`);

/**
 * Parse a briefing header window into its two endpoints.
 *
 * @param {string} windowStr e.g. "2026-04-24T19:00:00Z → 2026-05-05T20:30:00Z (~11 days)"
 * @returns {{ open: string, close: string } | null} null when no range is present
 */
export function parseWindowRange(windowStr) {
  if (typeof windowStr !== "string") return null;
  const m = windowStr.match(WINDOW_RANGE);
  return m ? { open: m[1], close: m[2] } : null;
}

/**
 * @param {string} openIso
 * @param {string} closeIso
 * @returns {string} "YYYY-MM-DD to YYYY-MM-DD (~N days)"
 */
export function formatWindow(openIso, closeIso) {
  const a = new Date(openIso);
  const b = new Date(closeIso);
  const days = Math.round((b - a) / (1000 * 60 * 60 * 24));
  const fmt = (d) => d.toISOString().slice(0, 10);
  return `${fmt(a)} to ${fmt(b)} (~${days} days)`;
}
