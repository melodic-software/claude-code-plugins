/**
 * Video-player presence helpers shared by the player modules and the adapters.
 *
 * Every platform answers "is the player element on this page?" with the same
 * DOM query, and every adapter resolves a configured selector against its own
 * default. The two differ only in how strictly they read the platform config,
 * which is why that strictness is an explicit argument here rather than a
 * choice baked into the helper.
 */

/**
 * Check whether an element matching `selector` exists on the page.
 *
 * `selector` is handed to `page.evaluate` as an argument rather than closed
 * over: the callback is serialized into the browser context, where this
 * module's bindings do not exist.
 *
 * @param {import('playwright').Page} page
 * @param {string} selector
 * @returns {Promise<boolean>} false when the page evaluation rejects
 */
export async function hasPlayerElement(page, selector) {
  return page.evaluate((sel) => !!document.querySelector(sel), selector).catch(() => false);
}

/**
 * The configured video-player selector, falling back to an adapter default.
 *
 * @param {object} platformCfg
 * @param {string} defaultSelector
 * @param {{ optionalConfig?: boolean }} [options] `optionalConfig: true` reads
 *   the config optionally, so a nullish `platformCfg` yields `defaultSelector`;
 *   the default reads it directly, so a nullish `platformCfg` raises a
 *   TypeError.
 * @returns {string}
 */
export function resolvePlayerSelector(
  platformCfg,
  defaultSelector,
  { optionalConfig = false } = {},
) {
  const configured = optionalConfig
    ? platformCfg?.videoPlayerSelector
    : platformCfg.videoPlayerSelector;
  return configured ?? defaultSelector;
}
