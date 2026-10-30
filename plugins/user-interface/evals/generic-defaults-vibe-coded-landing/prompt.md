---
schema_version: "1.1"
name: generic-defaults-vibe-coded-landing
description: "Happy path: a generated-looking landing page for a product that has not launched gets its invented social proof cut or flagged for real content rather than reworded, and its emoji feature markers replaced by real icons or dropped"
tags: [web, generic-defaults, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The revised page removes the invented user count, testimonial and logo wall (or leaves them out and asks for real ones) instead of rewording them, and no feature marker is an emoji The revised page sets a deliberate typeface for its text, or keeps the default font stack and states why."
---

This landing page looks vibe-coded, fix it. It's for Ledgerly, a bookkeeping app for farms that
launches next month, so nobody uses it yet. It's React with Tailwind. This run cannot write files,
so put the revised component in your reply.

```jsx
export default function Landing() {
  return (
    <main className="bg-gradient-to-br from-indigo-500 to-purple-600 text-white">
      <section className="text-center py-24">
        <span className="rounded-full bg-white/10 px-3 py-1 text-sm">✨ Announcing Ledgerly</span>
        <h1 className="mt-6 text-6xl font-black tracking-tight bg-gradient-to-r from-white to-cyan-300 bg-clip-text text-transparent">
          Build faster. Ship smarter.
        </h1>
        <p className="mt-4">The all-in-one platform for modern teams.</p>
        <a href="/signup" className="rounded-2xl bg-white text-indigo-600 px-6 py-3">Get started</a>
        <a href="#" className="ml-4">Learn more</a>
      </section>
      <section className="grid grid-cols-3 gap-6 px-12">
        <div className="rounded-2xl bg-white/10 backdrop-blur p-6">🚀 <h3>Fast</h3><p>Lightning quick books.</p></div>
        <div className="rounded-2xl bg-white/10 backdrop-blur p-6">🔒 <h3>Secure</h3><p>Bank-grade security.</p></div>
        <div className="rounded-2xl bg-white/10 backdrop-blur p-6">⚡ <h3>Powerful</h3><p>Everything you need.</p></div>
      </section>
      <section className="py-16 text-center">
        <p className="text-4xl font-bold">Trusted by 10,000+ farms</p>
        <blockquote>"Ledgerly changed how we run our farm." Sarah K., Owner, Green Acres</blockquote>
        <div className="flex justify-center gap-8">
          <img src="/logos/harvest-co.svg" alt="harvest-co.svg" />
          <img src="/logos/prairie-mills.svg" alt="prairie-mills.svg" />
        </div>
      </section>
    </main>
  );
}
```
