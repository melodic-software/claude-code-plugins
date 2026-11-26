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

export const componentStatus = (page, name) =>
  Array.isArray(page?.components) ? page.components.find((c) => c?.name === name && c.group !== true)?.status : undefined;

export const verdictOf = (status) => {
  if (typeof status !== "string") {
    return "unknown";
  }
  return status === "operational" ? "operational" : "degraded";
};

export async function readComponents({ fetchStatus: read = fetchStatus, components = COMPONENTS } = {}) {
  return Promise.all(
    components.map(async ({ key, url, name }) => {
      const host = new URL(url).host;
      const unknown = (reason) => ({ key, host, component: name, status: null, verdict: "unknown", reason });
      let page;
      try {
        page = await read(url);
      } catch (error) {
        return unknown(`${host} could not be read (${error?.message ?? error})`);
      }
      const status = componentStatus(page, name);
      const verdict = verdictOf(status);
      if (verdict === "unknown") {
        return unknown(`${host} lists no ${name} component with a status`);
      }
      return { key, host, component: name, status, verdict, reason: "" };
    }),
  );
}
