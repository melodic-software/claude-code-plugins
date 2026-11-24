const bodies = JSON.parse(process.env.CDN_PINS_FAKE_FETCH ?? "{}");
globalThis.fetch = async (url) => {
  const body = bodies[url];
  if (body === undefined) return { ok: false, status: 404 };
  const bytes = typeof body === "string" ? Buffer.from(body) : Buffer.from(body.base64, "base64");
  return { ok: true, status: 200, arrayBuffer: async () => bytes };
};
