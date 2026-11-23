import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Mutates providerLogos in place, replacing missing optional assets with null.
 *
 * @param {Record<string, string|null>} providerLogos
 * @returns {Promise<{available: string[], skipped: string[], missing: string[]}>}
 */
export async function resolveProviderLogos(providerLogos) {
  const available = [];
  const skipped = [];
  const missing = [];

  for (const [slug, relPath] of Object.entries(providerLogos)) {
    if (relPath === null) {
      skipped.push(`${slug} (intentionally null)`);
      continue;
    }

    const fullPath = path.resolve(__dirname, "..", relPath);
    try {
      await fs.access(fullPath);
      available.push(`${slug} → ${relPath}`);
    } catch {
      missing.push(`${slug} (${relPath})`);
      providerLogos[slug] = null;
    }
  }

  return { available, skipped, missing };
}
