#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/components
cat > package.json <<'JSON'
{ "name": "annual-report", "private": true, "type": "module",
  "scripts": { "dev": "vite" },
  "dependencies": { "react": "^18.3.1", "react-dom": "^18.3.1" },
  "devDependencies": { "vite": "^5.4.0", "@vitejs/plugin-react": "^4.3.0" } }
JSON
cat > vite.config.js <<'JS'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({ plugins: [react()] });
JS
cat > src/main.jsx <<'JS'
import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App.jsx';
createRoot(document.getElementById('root')).render(<App />);
JS
mkdir -p src/lab/torn-edge src/config
cat > src/config/torn-edge.json <<'JSON'
{ "seed": 4127, "depth": 18, "jaggedness": 0.73, "fiberDensity": 42 }
JSON
cat > src/lab/torn-edge/render.js <<'JS'
// Throwaway generator render logic: builds an SVG path for a torn edge from a config.
export function tornEdgePath({ seed, depth, jaggedness, fiberDensity }, width = 1200) {
  let s = seed; const rand = () => ((s = (s * 16807) % 2147483647) / 2147483647);
  const pts = [];
  for (let x = 0; x <= width; x += 1200 / fiberDensity) pts.push([x, depth * (1 - jaggedness * rand())]);
  return 'M0 0 ' + pts.map(([x, y]) => `L${x.toFixed(1)} ${y.toFixed(1)}`).join(' ') + ` L${width} 0 Z`;
}
JS
cat > src/lab/torn-edge/TornEdgeLab.jsx <<'JS'
// PROTOTYPE: throwaway generator. Delete after harvest.
import { useState } from 'react';
import { tornEdgePath } from './render.js';
const DEFAULTS = { seed: 1, depth: 12, jaggedness: 0.4, fiberDensity: 30 };
export default function TornEdgeLab() {
  const [cfg, setCfg] = useState(DEFAULTS);
  const save = () => fetch('/__lab/save', { method: 'POST', body: JSON.stringify(cfg) });
  return (<div><svg width="1200" height="40"><path d={tornEdgePath(cfg)} /></svg>
    <button onClick={save}>Save</button></div>);
}
JS
cat > src/components/ReportCover.jsx <<'JS'
export default function ReportCover() {
  return (<div className="cover"><img src="/hero.jpg" alt="" /><div className="cover-edge" /></div>);
}
JS
cat > src/App.jsx <<'JS'
import ReportCover from './components/ReportCover.jsx';
import TornEdgeLab from './lab/torn-edge/TornEdgeLab.jsx';
export default function App() {
  if (import.meta.env.DEV && location.pathname === '/lab/torn-edge') return <TornEdgeLab />;
  return <ReportCover />;
}
JS
