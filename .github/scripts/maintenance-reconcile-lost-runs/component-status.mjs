// component-status.mjs: the verdict for each outside service CI depends on,
// read from that service's own component on its status page: GitHub Actions
// (githubstatus.com), npm package installation (status.npmjs.org) and Claude
// Code (status.claude.com). A page's rollup, status.indicator, speaks for the
// whole page, not for the one component CI uses, so it is never read. No model.
//
// A verdict is one of:
// - operational: the component's status is operational;
// - degraded: the component lists any other status;
// - unknown: the page could not be read, or lists no such component with a
//   status.

export const ACTIONS = { key: "actions", url: "https://www.githubstatus.com/api/v2/components.json", name: "Actions" };
export const NPM_INSTALL = { key: "npm-install", url: "https://status.npmjs.org/api/v2/components.json", name: "Package installation" };
export const CLAUDE_CODE = { key: "claude-code", url: "https://status.claude.com/api/v2/components.json", name: "Claude Code" };
export const COMPONENTS = [ACTIONS, NPM_INSTALL, CLAUDE_CODE];

export async function fetchStatus(url) {
  const response = await fetch(url, { headers: { Accept: "application/json" }, signal: AbortSignal.timeout(15_000) });
  if (!response.ok) {
    throw new Error(`the status page answered ${response.status}`);
  }
  return response.json();
}

// The named component's status, or undefined when the page has none. A group
// of that name is not the component.
export const componentStatus = (page, name) =>
  Array.isArray(page?.components) ? page.components.find((c) => c?.name === name && c.group !== true)?.status : undefined;

export const verdictOf = (status) => {
  if (typeof status !== "string") {
    return "unknown";
  }
  return status === "operational" ? "operational" : "degraded";
};

// Each component's verdict, in the order given: { key, host, component,
// status, verdict, reason }, where status is the page's string or null and
// reason says why an unknown verdict is unknown ("" otherwise).
export async function readComponents({ fetchStatus: read = fetchStatus, components = COMPONENTS } = {}) {
  return Promise.all(
    components.map(async ({ key, url, name }) => {
      const host = new URL(url).host;
      let page;
      try {
        page = await read(url);
      } catch (error) {
        return { key, host, component: name, status: null, verdict: "unknown", reason: `${host} could not be read (${error?.message ?? error})` };
      }
      const status = componentStatus(page, name);
      const verdict = verdictOf(status);
      return {
        key,
        host,
        component: name,
        status: typeof status === "string" ? status : null,
        verdict,
        reason: verdict === "unknown" ? `${host} lists no ${name} component with a status` : "",
      };
    }),
  );
}
