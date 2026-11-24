"use strict";

/**
 * Resolve an npm tool version for composite actions.
 *
 * Precedence: explicit input → exact package.json pin → reviewed fallback.
 * Ranges / aliases / conflicting declarations fail closed.
 */

const fs = require("node:fs");
const path = require("node:path");

const EXACT_SEMVER = /^\d+\.\d+\.\d+$/u;

class ResolveError extends Error {
  constructor(message) {
    super(message);
    this.name = "ResolveError";
  }
}

function readPackageJson(packageJsonPath) {
  let raw;
  try {
    raw = fs.readFileSync(packageJsonPath, "utf8");
  } catch (error) {
    if (error && error.code === "ENOENT") {
      return null;
    }
    throw error;
  }
  try {
    return JSON.parse(raw);
  } catch {
    throw new ResolveError(
      `could not parse ${packageJsonPath} as JSON for tool-version resolution`,
    );
  }
}

function collectDeclaredVersions(manifest, packageName) {
  const sections = ["devDependencies", "dependencies", "optionalDependencies"];
  const found = [];
  for (const section of sections) {
    const block = manifest[section];
    if (block === null || typeof block !== "object" || Array.isArray(block)) {
      continue;
    }
    if (!Object.hasOwn(block, packageName)) {
      continue;
    }
    const value = block[packageName];
    if (typeof value !== "string" || value.trim() === "") {
      throw new ResolveError(
        `${packageName} in ${section} must be a non-empty string pin`,
      );
    }
    found.push({ section, version: value.trim() });
  }
  return found;
}

function resolveNpmToolVersion({
  versionInput = "",
  fallbackVersion,
  packageName,
  packageJsonPath = "package.json",
}) {
  if (
    typeof fallbackVersion !== "string" ||
    !EXACT_SEMVER.test(fallbackVersion)
  ) {
    throw new ResolveError(
      `fallback version must be an exact major.minor.patch, got ${JSON.stringify(fallbackVersion)}`,
    );
  }
  if (typeof packageName !== "string" || packageName.trim() === "") {
    throw new ResolveError("package name is required");
  }

  const input = typeof versionInput === "string" ? versionInput.trim() : "";
  if (input !== "") {
    if (!EXACT_SEMVER.test(input)) {
      throw new ResolveError(
        `version input must be an exact major.minor.patch, got ${JSON.stringify(input)}`,
      );
    }
    return { version: input, source: "input" };
  }

  const manifest = readPackageJson(packageJsonPath);
  const declared =
    manifest === null ? [] : collectDeclaredVersions(manifest, packageName);
  if (declared.length === 0) {
    return { version: fallbackVersion, source: "fallback" };
  }

  const unique = [...new Set(declared.map((entry) => entry.version))];
  if (unique.length !== 1) {
    const detail = declared
      .map((entry) => `${entry.section}=${entry.version}`)
      .join(", ");
    throw new ResolveError(
      `conflicting ${packageName} pins in ${path.basename(packageJsonPath)}: ${detail}`,
    );
  }

  const pin = unique[0];
  if (!EXACT_SEMVER.test(pin)) {
    throw new ResolveError(
      `${packageName} pin ${JSON.stringify(pin)} is not an exact major.minor.patch; ` +
        "refuse ranged/aliased specs so CI never resolves registry-latest at run time",
    );
  }

  return { version: pin, source: "package.json" };
}

function runCli(env) {
  const { version, source } = resolveNpmToolVersion({
    versionInput: env.VERSION_INPUT,
    fallbackVersion: env.FALLBACK_VERSION,
    packageName: env.PACKAGE_NAME,
    packageJsonPath: env.PACKAGE_JSON,
  });
  process.stdout.write(`resolved version=${version} source=${source}\n`);
  if (env.GITHUB_OUTPUT) {
    fs.appendFileSync(
      env.GITHUB_OUTPUT,
      `version=${version}\nsource=${source}\n`,
      "utf8",
    );
  }
}

if (require.main === module) {
  try {
    runCli(process.env);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`::error::${message}\n`);
    process.exitCode = 1;
  }
}

module.exports = Object.freeze({
  ResolveError,
  resolveNpmToolVersion,
});
