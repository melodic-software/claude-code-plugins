// The managed settings rule run-claude-cli and apply-claude-managed-settings
// share: what /etc/claude-code/managed-settings.json must set, and the one
// base URL besides the public API it may pin.
//
// Run as a script (apply-claude-managed-settings), it checks SETTINGS against
// LOOPBACK_BASE_URL and exits 1 with an error annotation on any problem.
"use strict";

const PINNED_BASE_URL = "https://api.anthropic.com";
// URL hostnames as WHATWG URL gives them; an IPv6 hostname keeps its brackets.
const LOOPBACK_HOSTS = ["127.0.0.1", "[::1]"];

// The base URL the settings must pin: the public API when the
// loopback-base-url opt-in is empty, else the opt-in itself, which must be
// exactly `http://127.0.0.1:<port>` or `http://[::1]:<port>` (a key proxy on
// the runner's loopback). Comparing with the URL's own serialization refuses
// any path, query, fragment, userinfo, default or zero port, and any other
// spelling of the host. Returns { baseUrl } or { problem }.
function expectedBaseUrl(optIn) {
  const text = (optIn ?? "").trim();
  if (text === "") return { baseUrl: PINNED_BASE_URL };
  let url = null;
  try {
    url = new URL(text);
  } catch {
    // Not a URL: refused below.
  }
  const loopback =
    url !== null &&
    url.protocol === "http:" &&
    LOOPBACK_HOSTS.includes(url.hostname) &&
    url.port !== "" &&
    url.port !== "0" &&
    text === `http://${url.host}`;
  return loopback
    ? { baseUrl: text }
    : {
        problem: `loopback-base-url ${JSON.stringify(text)} is not exactly http://127.0.0.1:<port> or http://[::1]:<port>`,
      };
}

// What the parsed settings get wrong, or null: they must set apiKeyHelper,
// env.ANTHROPIC_BASE_URL to baseUrl, permissions.disableBypassPermissionsMode
// to "disable", and allowManagedHooksOnly or disableAllHooks to true.
function settingsProblem(settings, baseUrl) {
  if (
    typeof settings !== "object" ||
    settings === null ||
    Array.isArray(settings) ||
    !Object.hasOwn(settings, "apiKeyHelper")
  ) {
    return "does not pin apiKeyHelper";
  }
  if (settings.env?.ANTHROPIC_BASE_URL !== baseUrl) {
    return `does not pin env.ANTHROPIC_BASE_URL to ${baseUrl}`;
  }
  if (settings.permissions?.disableBypassPermissionsMode !== "disable") {
    return 'does not set permissions.disableBypassPermissionsMode to "disable"';
  }
  if (
    settings.allowManagedHooksOnly !== true &&
    settings.disableAllHooks !== true
  ) {
    return "sets neither allowManagedHooksOnly nor disableAllHooks to true";
  }
  return null;
}

function checkApplied(env) {
  const { baseUrl, problem } = expectedBaseUrl(env.LOOPBACK_BASE_URL);
  if (problem !== undefined) return problem;
  let settings;
  try {
    settings = JSON.parse(env.SETTINGS ?? "");
  } catch {
    return "settings is not JSON";
  }
  const wrong = settingsProblem(settings, baseUrl);
  return wrong === null ? null : `settings ${wrong}`;
}

if (require.main === module) {
  const problem = checkApplied(process.env);
  if (problem !== null) {
    process.stdout.write(
      `::error title=apply-claude-managed-settings::${problem}\n`,
    );
    process.exitCode = 1;
  }
}

module.exports = { PINNED_BASE_URL, expectedBaseUrl, settingsProblem };
