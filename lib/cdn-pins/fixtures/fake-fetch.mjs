const bodies = JSON.parse(process.env.CDN_PINS_FAKE_FETCH ?? "{}");
globalThis.fetch = async (url) => {
  const body = bodies[url];
  return body === undefined ? { ok: false, status: 404 } : { ok: true, status: 200, arrayBuffer: async () => Buffer.from(body) };
};
