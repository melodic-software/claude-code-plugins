// Anti-bot pacing — track navs/session, enforce cap, random delays.

export class AntiBot {
  constructor({ cap = 90, minDelayMs = 2000, maxDelayMs = 5000 } = {}) {
    this.cap = cap;
    this.minDelayMs = minDelayMs;
    this.maxDelayMs = maxDelayMs;
    this.navsUsed = 0;
  }

  static fromMaster(master) {
    const ab = master.anti_bot || {};
    const cfg = master.config || {};
    const inst = new AntiBot({
      cap: ab.cap ?? 90,
      minDelayMs: cfg.delay_min_ms ?? 2000,
      maxDelayMs: cfg.delay_max_ms ?? 5000,
    });
    inst.navsUsed = 0; // session counter resets on each invocation
    return inst;
  }

  incrementNav(count = 1) {
    this.navsUsed += count;
  }

  shouldPause() {
    return this.navsUsed >= this.cap;
  }

  async randomDelay() {
    const ms = this.minDelayMs + Math.floor(Math.random() * (this.maxDelayMs - this.minDelayMs));
    await new Promise((r) => setTimeout(r, ms));
  }
}
