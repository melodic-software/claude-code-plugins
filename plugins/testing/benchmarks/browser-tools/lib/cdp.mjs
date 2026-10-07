// Minimal Chrome DevTools Protocol driver used only for tool-neutral reference solutions: it proves
// each case is solvable and its grader is wired, without going through either tool under test.
// Needs Node 22+ (global WebSocket) and a Chromium binary (CHROME_PATH, or the first one found).

import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export function findChrome() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const roots = [process.env.PLAYWRIGHT_BROWSERS_PATH, join(process.env.HOME ?? "", ".cache/ms-playwright")].filter(Boolean);
  for (const root of roots) {
    if (!existsSync(root)) continue;
    for (const d of readdirSync(root).filter((n) => n.startsWith("chromium-")).sort().reverse()) {
      for (const rel of ["chrome-linux/chrome", "chrome-linux64/chrome", "chrome-mac/Chromium.app/Contents/MacOS/Chromium", "chrome-win/chrome.exe"]) {
        const p = join(root, d, rel);
        if (existsSync(p)) return p;
      }
    }
  }
  for (const p of ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome"]) if (existsSync(p)) return p;
  throw new Error("No Chromium found: set CHROME_PATH");
}

export async function launch({ downloadDir } = {}) {
  const profile = mkdtempSync(join(tmpdir(), "bt-ref-"));
  const proc = spawn(findChrome(), ["--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`, "--no-first-run", "--no-sandbox", "about:blank"], {
    stdio: ["ignore", "ignore", "pipe"],
  });
  const wsUrl = await new Promise((resolve, reject) => {
    let buf = "";
    proc.stderr.on("data", (d) => {
      buf += d;
      const m = buf.match(/DevTools listening on (ws:\/\/\S+)/);
      if (m) resolve(m[1]);
    });
    proc.on("exit", () => reject(new Error(`chrome exited: ${buf.slice(-400)}`)));
  });
  const ws = new WebSocket(wsUrl);
  await new Promise((r) => ws.addEventListener("open", r, { once: true }));
  let seq = 0;
  const pending = new Map();
  const listeners = [];
  ws.addEventListener("message", (e) => {
    const msg = JSON.parse(e.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
    } else for (const l of listeners) l(msg);
  });
  const send = (method, params = {}, sessionId) =>
    new Promise((resolve, reject) => {
      const id = ++seq;
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params, sessionId }));
    });
  if (downloadDir) await send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: downloadDir });

  async function attach(targetId) {
    const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
    await send("Page.enable", {}, sessionId);
    await send("Runtime.enable", {}, sessionId);
    return page(sessionId);
  }
  function page(sessionId) {
    const s = (m, p) => send(m, p, sessionId);
    const api = {
      dialogAction: null,
      async goto(url) {
        await s("Page.navigate", { url });
        await api.waitFor("document.readyState === 'complete'");
      },
      async eval(expression) {
        const r = await s("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
        if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
        return r.result.value;
      },
      async waitFor(expression, timeout = 15000) {
        const end = Date.now() + timeout;
        while (Date.now() < end) {
          try {
            if (await api.eval(expression)) return;
          } catch {}
          await new Promise((r) => setTimeout(r, 100));
        }
        throw new Error(`timeout waiting for ${expression}`);
      },
      async clickAt(x, y) {
        for (const type of ["mousePressed", "mouseReleased"]) await s("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1 });
      },
      async setFiles(selector, files) {
        const { root } = await s("DOM.getDocument", { depth: -1, pierce: true });
        const { nodeId } = await s("DOM.querySelector", { nodeId: root.nodeId, selector });
        await s("DOM.setFileInputFiles", { nodeId, files });
      },
    };
    listeners.push((msg) => {
      if (msg.sessionId === sessionId && msg.method === "Page.javascriptDialogOpening")
        s("Page.handleJavaScriptDialog", { accept: api.dialogAction === "accept" });
    });
    return api;
  }

  const { targetInfos } = await send("Target.getTargets");
  const first = targetInfos.find((t) => t.type === "page");
  return {
    page: await attach(first.targetId),
    async newPage() {
      const { targetId } = await send("Target.createTarget", { url: "about:blank" });
      return attach(targetId);
    },
    async close() {
      ws.close();
      proc.kill();
    },
  };
}
