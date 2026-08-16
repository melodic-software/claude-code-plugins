/**
 * Shared <meta> scrape for adapter metadata phases.
 *
 * The predicate runs inside the page, so the per-adapter part travels as data:
 * og: and twitter: properties always match, plus any caller-supplied property
 * substrings. A scrape failure yields {} — metadata is best-effort.
 */
export async function fetchMetaTags(page, extraSubstrings = []) {
  return page
    .evaluate((extra) => {
      const tags = {};
      for (const meta of document.querySelectorAll("meta")) {
        const prop = meta.getAttribute("property") || meta.getAttribute("name");
        if (
          prop?.startsWith("og:") ||
          prop?.startsWith("twitter:") ||
          extra.some((s) => prop?.includes(s))
        ) {
          tags[prop] = meta.getAttribute("content");
        }
      }
      return tags;
    }, extraSubstrings)
    .catch(() => ({}));
}
