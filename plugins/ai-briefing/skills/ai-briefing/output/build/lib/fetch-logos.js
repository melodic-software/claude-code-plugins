// Pre-flight: fetch missing provider logos from simpleicons CDN.
// Slide-generation.md "Provider logo registry" lists the canonical slug→file map.
// New providers added to providerLogos in slides-data.js with non-existent files
// get auto-fetched here. 404s downgrade to null (text-only header).
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ASSETS_DIR = path.resolve(__dirname, "..", "assets");

const CDN = (slug) => `https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/${slug}.svg`;

/**
 * Ensure each non-null entry in providerLogos resolves to a file on disk.
 * Mutates providerLogos in place — sets value to null if fetch 404s.
 *
 * @param {Record<string, string|null>} providerLogos  slug → "assets/logo-<slug>.svg" or null
 * @returns {{fetched: string[], skipped: string[], failed: string[]}}
 */
export async function ensureProviderLogos(providerLogos) {
  await fs.mkdir(ASSETS_DIR, { recursive: true });
  const fetched = [];
  const skipped = [];
  const failed = [];

  for (const [slug, relPath] of Object.entries(providerLogos)) {
    if (relPath === null) {
      skipped.push(`${slug} (intentionally null)`);
      continue;
    }
    const fullPath = path.resolve(__dirname, "..", relPath);
    try {
      await fs.access(fullPath);
      skipped.push(`${slug} (cached)`);
      continue;
    } catch { /* missing — fetch */ }

    // Slug-from-path: prefer explicit slug; fallback to filename component
    const fetchSlug = slug === "vscode" ? "visualstudiocode"
      : slug === "xai" ? "x"
      : slug;

    try {
      const res = await fetch(CDN(fetchSlug));
      if (!res.ok) {
        failed.push(`${slug} (HTTP ${res.status} from ${CDN(fetchSlug)})`);
        providerLogos[slug] = null;
        continue;
      }
      const svg = await res.text();
      await fs.writeFile(fullPath, svg, "utf-8");
      fetched.push(`${slug} → ${relPath}`);
    } catch (e) {
      failed.push(`${slug} (${e.message})`);
      providerLogos[slug] = null;
    }
  }

  return { fetched, skipped, failed };
}
