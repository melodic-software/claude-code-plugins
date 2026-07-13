/**
 * Mux video player module.
 *
 * Reads the HLS source URL from a Mux player DOM element.
 * Simple DOM read — no network interception needed.
 */

/**
 * Get the HLS URL from a Mux player element's src property.
 *
 * @param {import('playwright').Page} page
 * @param {string} selector — CSS selector for the mux-player element
 * @returns {Promise<string>}
 */
export async function getHlsUrl(page, selector) {
  const url = await page.evaluate((sel) => {
    const player = document.querySelector(sel);
    return player?.src || null;
  }, selector);

  if (!url) {
    throw new Error(`Video player not found (selector: ${selector})`);
  }
  return url;
}

/**
 * Check if a Mux player element exists on the page.
 *
 * @param {import('playwright').Page} page
 * @param {string} selector — CSS selector for the mux-player element
 * @returns {Promise<boolean>}
 */
export async function hasMuxPlayer(page, selector) {
  return page.evaluate((sel) => !!document.querySelector(sel), selector).catch(() => false);
}
