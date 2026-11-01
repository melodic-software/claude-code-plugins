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
cat > src/components/SectionDivider.jsx <<'JS'
export default function SectionDivider() {
  return <svg width="100%" height="24" viewBox="0 0 1200 24"><path d="M0 12 Q300 0 600 12 T1200 12" fill="none" stroke="currentColor" /></svg>;
}
JS
cat > src/App.jsx <<'JS'
import SectionDivider from './components/SectionDivider.jsx';
export default function App() {
  return (<main><h2>Features</h2><SectionDivider /><h2>Pricing</h2></main>);
}
JS
