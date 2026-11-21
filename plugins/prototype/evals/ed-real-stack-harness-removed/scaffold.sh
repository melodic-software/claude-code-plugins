#!/usr/bin/env bash
# A shipments app mid-way through a real-stack explore-directions run (sub-shape A): three variant
# files and a switcher beside the /shipments page, its mount block, and the notes harness
# (prototype-harness/ plus the marked lines in vite.config.js and src/main.jsx). The person has
# replied, so step 5 records the pick and removes every prototype part.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

cat >package.json <<'JSON'
{ "name": "shipments", "private": true, "type": "module",
  "scripts": { "dev": "vite", "build": "vite build" },
  "dependencies": { "react": "^18.3.1", "react-dom": "^18.3.1" },
  "devDependencies": { "vite": "^5.4.0", "@vitejs/plugin-react": "^4.3.0" } }
JSON
mkdir -p docs/decisions src/pages/shipments-variants prototype-harness
cat >docs/decisions/README.md <<'MD'
# Decisions

UI decisions: one file per screen, `docs/decisions/ui-<screen>.md` (for `/shipments`,
`docs/decisions/ui-shipments.md`).
MD
cat >index.html <<'HTML'
<!doctype html>
<html><head><meta charset="utf-8"><title>Shipments</title></head>
<body><div id="root"></div><script type="module" src="/src/main.jsx"></script></body></html>
HTML
cat >vite.config.js <<'JS'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
const plugins = [react()];
export default defineConfig({ plugins });
JS
cat >src/pages/ParcelList.jsx <<'JS'
export default function ParcelList({ parcels }) {
  return (<ul>{parcels.map((p) => <li key={p.id} data-testid="shipments-parcel-row">{p.id} {p.status}</li>)}</ul>);
}
JS
git add .
git commit -q -m "chore: scaffold shipments app"

cat >vite.config.js <<'JS'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { harnessFence } from './prototype-harness/harness-fence.mjs'; // data-prototype-harness
const plugins = [react()];
plugins.push({ name: 'notes-fence', configureServer: (s) => s.middlewares.use(harnessFence('http://localhost:41234')) }); // data-prototype-harness
export default defineConfig({ plugins });
JS
cat >prototype-harness/harness-fence.mjs <<'JS'
// data-prototype-harness: copy of the prototype plugin's notes-bridge/harness-fence.mjs (body elided in this fixture).
import { canonicalOrigin } from './dev-origin.mjs';
export function harnessFence(bridgeOrigin) {
  const policy = `frame-ancestors ${canonicalOrigin(bridgeOrigin)}`;
  return (req, res, next) => { res.setHeader('Content-Security-Policy', policy); next(); };
}
JS
cat >prototype-harness/dev-origin.mjs <<'JS'
// data-prototype-harness: copy of the prototype plugin's notes-bridge/dev-origin.mjs (body elided in this fixture).
export function canonicalOrigin(input) {
  if (new URL(input).origin !== input) throw new Error(`${input} is not its own origin`);
  return input;
}
JS
cat >prototype-harness/proto-pin.js <<'JS'
// data-prototype-harness: copy of the prototype plugin's notes-bridge/proto-pin.js (body elided in this fixture).
(() => { if (window.parent !== window) window.parent.postMessage({ type: 'ready', controls: null, data: [], content: null }, '*'); })();
JS
cat >prototype-harness/mount.js <<'JS'
// data-prototype-harness: loads the notes frame helper into the route, dev only.
import helper from './proto-pin.js?raw';
const s = document.createElement('script');
s.setAttribute('data-prototype-harness', '');
s.textContent = helper;
document.head.append(s);
JS
cat >src/main.jsx <<'JS'
import React from 'react';
import { createRoot } from 'react-dom/client';
import Shipments from './pages/Shipments.jsx';
if (import.meta.env.DEV) import('../prototype-harness/mount.js'); // data-prototype-harness
createRoot(document.getElementById('root')).render(<Shipments />);
JS
cat >src/pages/shipments-variants/VariantA.jsx <<'JS'
// PROTOTYPE: shipments-layout variant A (Ledger). Delete after the pick.
export default function VariantA({ parcels }) {
  return (<table data-testid="shipments-parcel-table"><tbody>{parcels.map((p) => <tr key={p.id}><td>{p.id}</td><td>{p.status}</td></tr>)}</tbody></table>);
}
JS
cat >src/pages/shipments-variants/VariantB.jsx <<'JS'
// PROTOTYPE: shipments-layout variant B (Cards). Delete after the pick.
export default function VariantB({ parcels }) {
  return (<div>{parcels.map((p) => <article key={p.id} data-testid="shipments-parcel-card"><h3>Arrives {p.eta}</h3><p>{p.status}</p></article>)}</div>);
}
JS
cat >src/pages/shipments-variants/VariantC.jsx <<'JS'
// PROTOTYPE: shipments-layout variant C (Map). Delete after the pick.
export default function VariantC({ parcels }) {
  return (<div><div className="map" /><select data-testid="shipments-region-filter"><option>All regions</option></select><p>{parcels.length} parcels</p></div>);
}
JS
cat >src/pages/shipments-variants/Switcher.jsx <<'JS'
// PROTOTYPE: shipments-layout switcher. Delete after the pick.
import VariantA from './VariantA.jsx';
import VariantB from './VariantB.jsx';
import VariantC from './VariantC.jsx';
const VARIANTS = { A: VariantA, B: VariantB, C: VariantC };
export default function Switcher({ parcels }) {
  const key = new URLSearchParams(location.search).get('variant') || 'A';
  const V = VARIANTS[key] || VariantA;
  return <V parcels={parcels} />;
}
JS
cat >src/pages/Shipments.jsx <<'JS'
import ParcelList from './ParcelList.jsx';
// PROTOTYPE shipments-layout mount: start
import Switcher from './shipments-variants/Switcher.jsx';
// PROTOTYPE shipments-layout mount: end
const parcels = [{ id: 'P-1', status: 'In transit', eta: 'Tue 14 May' }, { id: 'P-2', status: 'Delivered', eta: 'Mon 13 May' }];
export default function Shipments() {
  // PROTOTYPE shipments-layout mount: start
  if (import.meta.env.DEV) return <Switcher parcels={parcels} />;
  // PROTOTYPE shipments-layout mount: end
  return <ParcelList parcels={parcels} />;
}
JS
git add .
git commit -q -m "chore: mount the shipments-layout prototype and its notes harness"
