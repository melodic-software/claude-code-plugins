/**
 * Portable temp-session paths for work-slice artifacts.
 * Serialized form uses `{tmp}` prefix (OS temp dir at resolve time).
 */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const TEMP_PATH_PREFIX = "{tmp}";

const LEADING_PATH_SEP_RE = /^[/\\]/;

/**
 * @param {string} dir
 * @returns {string}
 */
function resolveTmpRoot(dir) {
  try {
    return fs.realpathSync.native(dir);
  } catch {
    return path.resolve(dir);
  }
}

/**
 * Strip accidental prefixes before an embedded `{tmp}` token.
 *
 * @param {string} value
 * @returns {string}
 */
export function normalizePortableTempPath(value) {
  if (!value) return value;
  const idx = value.indexOf(TEMP_PATH_PREFIX);
  if (idx > 0) {
    return value.slice(idx).replace(/\\/g, "/");
  }
  if (value.startsWith(TEMP_PATH_PREFIX)) {
    return value.replace(/\\/g, "/");
  }
  return serializeTempPath(value);
}

/**
 * @param {string} absolutePath
 * @returns {string}
 */
export function serializeTempPath(absolutePath) {
  if (absolutePath.startsWith(TEMP_PATH_PREFIX)) {
    return absolutePath.replace(/\\/g, "/");
  }

  const tmpRoot = resolveTmpRoot(os.tmpdir());
  let normalized;
  try {
    normalized = fs.realpathSync.native(absolutePath);
  } catch {
    const relFromTmp = path.relative(path.resolve(os.tmpdir()), path.resolve(absolutePath));
    if (!relFromTmp.startsWith("..") && !path.isAbsolute(relFromTmp)) {
      normalized = path.join(tmpRoot, relFromTmp);
    } else {
      normalized = path.resolve(absolutePath);
    }
  }

  if (normalized === tmpRoot || normalized.startsWith(`${tmpRoot}${path.sep}`)) {
    const suffix = normalized.slice(tmpRoot.length).replace(/\\/g, "/");
    return `${TEMP_PATH_PREFIX}${suffix}`;
  }
  return normalized.replace(/\\/g, "/");
}

/**
 * @param {string} serialized
 * @returns {string}
 */
export function resolveTempPath(serialized) {
  if (!serialized) return serialized;
  if (serialized.startsWith(TEMP_PATH_PREFIX)) {
    const suffix = serialized.slice(TEMP_PATH_PREFIX.length).replace(/\//g, path.sep);
    return path.join(os.tmpdir(), suffix.replace(LEADING_PATH_SEP_RE, ""));
  }
  return serialized;
}

/**
 * @param {{ workDir?: string, framesDir?: string, contactSheetsDir?: string, acquiredAt?: string }} session
 * @returns {{ workDir?: string, framesDir?: string, contactSheetsDir?: string, acquiredAt?: string }}
 */
export function serializeTempSession(session) {
  if (!session) return session;
  return {
    ...session,
    workDir: session.workDir ? normalizePortableTempPath(session.workDir) : undefined,
    framesDir: session.framesDir ? normalizePortableTempPath(session.framesDir) : undefined,
    contactSheetsDir: session.contactSheetsDir
      ? normalizePortableTempPath(session.contactSheetsDir)
      : undefined,
  };
}

/**
 * @param {{ workDir?: string, framesDir?: string, contactSheetsDir?: string, acquiredAt?: string }} session
 * @returns {{ workDir?: string, framesDir?: string, contactSheetsDir?: string, acquiredAt?: string }}
 */
export function resolveTempSession(session) {
  if (!session) return session;
  return {
    ...session,
    workDir: session.workDir ? resolveTempPath(session.workDir) : undefined,
    framesDir: session.framesDir ? resolveTempPath(session.framesDir) : undefined,
    contactSheetsDir: session.contactSheetsDir
      ? resolveTempPath(session.contactSheetsDir)
      : undefined,
  };
}

/**
 * @param {string} framesDir
 * @param {string} fileName
 * @returns {string}
 */
export function resolveFramePath(framesDir, fileName) {
  return path.join(resolveTempPath(framesDir), fileName);
}
