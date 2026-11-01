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
