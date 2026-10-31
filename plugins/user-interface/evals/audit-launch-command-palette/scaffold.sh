#!/usr/bin/env bash
# Seeds a small Next.js app with a command palette and two launch leftovers.
set -euo pipefail

mkdir -p app/components lib
cat > package.json <<'JSON'
{
  "name": "lesson-notes",
  "private": true,
  "scripts": { "dev": "next dev", "build": "next build" },
  "dependencies": { "next": "15.0.0", "react": "19.0.0", "react-dom": "19.0.0", "leva": "0.10.0", "motion": "12.0.0" }
}
JSON
cat > app/layout.tsx <<'TSX'
import { Leva } from "leva";
import { CommandPalette } from "./components/CommandPalette";
import "./globals.css";

export const metadata = { title: "Lesson notes", description: "Search your lesson notes." };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Leva />
        <CommandPalette />
        {children}
      </body>
    </html>
  );
}
TSX
cat > app/globals.css <<'CSS'
body { margin: 0; font-family: system-ui, sans-serif; }
.backdrop { position: fixed; inset: 0; background: oklch(0 0 0 / 0.2); }
.palette { position: fixed; inset-block-start: 15vh; inset-inline: 0; margin-inline: auto; inline-size: min(600px, 90vw); border-radius: 12px; background: Canvas; }
.palette input { inline-size: 100%; font-size: 16px; padding: 12px; border: 0; }
CSS
cat > app/components/CommandPalette.tsx <<'TSX'
"use client";
import { useEffect, useState } from "react";
import { motion } from "motion/react";
import { search } from "../../lib/search";

export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") setOpen((o) => !o);
      if (e.key === "Escape") setOpen(false);
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  if (!open) return null;
  const results = search(query);
  return (
    <>
      <div className="backdrop" onClick={() => setOpen(false)} />
      <motion.div
        className="palette"
        role="dialog"
        aria-modal="true"
        initial={{ opacity: 0, scale: 0.97, y: -4 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        transition={{ duration: 0.2 }}
      >
        <input autoFocus placeholder="Search lessons" value={query} onChange={(e) => setQuery(e.target.value)} />
        <ul>
          {results.map((r) => (
            <li key={r.href}><a href={r.href}>{r.title}</a></li>
          ))}
        </ul>
      </motion.div>
    </>
  );
}
TSX
cat > lib/search.ts <<'TS'
const index = [
  { title: "Easing basics", href: "/lessons/easing" },
  { title: "Spring physics", href: "/lessons/springs" },
];

export function search(query: string) {
  return index.filter((item) => item.title.toLowerCase().includes(query.toLowerCase()));
}
TS
cat > lib/auth.ts <<'TS'
export async function getSession() {
  const res = await fetch("/api/session");
  const session = await res.json();
  console.log("session", session);
  return session;
}
TS
