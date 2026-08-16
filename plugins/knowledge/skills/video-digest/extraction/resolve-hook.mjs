/**
 * ESM resolve hook: fall back to `${CLAUDE_PLUGIN_DATA}/node_modules` for bare
 * specifiers the pipeline can't find inside the cache-isolated plugin directory.
 *
 * The extraction dependencies (`@melodic/*`, `imghash`) are installed into the
 * persistent plugin data directory, not into the plugin itself (setup-deps.mjs).
 * NODE_PATH — the CommonJS mechanism for this — is ignored by the ESM loader, so
 * a resolve hook is the ESM-native equivalent. When node's default resolution
 * fails, this retries with `parentURL` pointing into the data directory's
 * `node_modules`, delegating to node's own resolver so package `exports` maps
 * and transitive dependencies resolve correctly from there.
 */
import path from "node:path";
import { pathToFileURL } from "node:url";

const dataModules = process.env.CLAUDE_PLUGIN_DATA
  ? pathToFileURL(path.join(process.env.CLAUDE_PLUGIN_DATA, "node_modules", "__resolve-anchor__.js")).href
  : null;

function isBareSpecifier(specifier) {
  return (
    !specifier.startsWith(".") &&
    !specifier.startsWith("/") &&
    !specifier.startsWith("node:") &&
    !specifier.startsWith("file:")
  );
}

export async function resolve(specifier, context, next) {
  try {
    return await next(specifier, context);
  } catch (error) {
    if (
      dataModules &&
      error?.code === "ERR_MODULE_NOT_FOUND" &&
      isBareSpecifier(specifier)
    ) {
      return next(specifier, { ...context, parentURL: dataModules });
    }
    throw error;
  }
}
